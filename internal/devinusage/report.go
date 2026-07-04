package devinusage

import (
	"encoding/json"
	"fmt"
	"io"
	"os"
	"os/exec"
	"sort"
	"strconv"
	"strings"
	"time"
)

// AggregateKey identifies a reporting bucket.
type AggregateKey string

// Aggregate holds summed token usage and cost for one bucket.
type Aggregate struct {
	Key         AggregateKey
	Label       string
	Models      map[string]struct{}
	Input       int64
	Output      int64
	CacheRead   int64
	CacheCreate int64
	Cost        float64
}

func newAggregate(key AggregateKey, label string) *Aggregate {
	return &Aggregate{
		Key:    key,
		Label:  label,
		Models: make(map[string]struct{}),
	}
}

func (a *Aggregate) add(r UsageRecord, cost float64) {
	a.Input += r.InputTokens
	a.Output += r.OutputTokens
	a.CacheRead += r.CacheReadTokens
	a.CacheCreate += r.CacheCreationTokens
	a.Cost += cost
	if r.Model != "" {
		a.Models[r.Model] = struct{}{}
	}
}

func (a *Aggregate) modelList() []string {
	models := make([]string, 0, len(a.Models))
	for m := range a.Models {
		models = append(models, m)
	}
	sort.Strings(models)
	return models
}

func AggregateBy(records []UsageRecord, prices map[string]ModelPrice, mode string) []*Aggregate {
	buckets := make(map[AggregateKey]*Aggregate)
	for _, r := range records {
		cost := EstimateCost(prices, r.Model, r.InputTokens, r.OutputTokens, r.CacheReadTokens, r.CacheCreationTokens)
		var key AggregateKey
		var label string
		switch mode {
		case "daily":
			key = AggregateKey(r.Timestamp.Format("2006-01-02"))
			label = string(key)
		case "monthly":
			key = AggregateKey(r.Timestamp.Format("2006-01"))
			label = string(key)
		case "session":
			key = AggregateKey(r.SessionID)
			label = SessionLabel(r)
		default:
			key = AggregateKey(r.Timestamp.Format("2006-01-02"))
			label = string(key)
		}
		b, ok := buckets[key]
		if !ok {
			b = newAggregate(key, label)
			buckets[key] = b
		}
		b.add(r, cost)
	}

	result := make([]*Aggregate, 0, len(buckets))
	for _, b := range buckets {
		result = append(result, b)
	}
	sort.Slice(result, func(i, j int) bool {
		return result[i].Key < result[j].Key
	})
	return result
}

func SessionLabel(r UsageRecord) string {
	if r.SessionTitle != "" {
		return fmt.Sprintf("%s (%s)", r.SessionID, r.SessionTitle)
	}
	return r.SessionID
}

// ModelBreakdown aggregates usage per model within a bucket.
type ModelBreakdown struct {
	Model       string
	Input       int64
	Output      int64
	CacheRead   int64
	CacheCreate int64
	Cost        float64
}

func BreakdownByModel(records []UsageRecord, prices map[string]ModelPrice, keyFn func(UsageRecord) AggregateKey) map[AggregateKey][]ModelBreakdown {
	groups := make(map[AggregateKey]map[string]*ModelBreakdown)
	for _, r := range records {
		key := keyFn(r)
		cost := EstimateCost(prices, r.Model, r.InputTokens, r.OutputTokens, r.CacheReadTokens, r.CacheCreationTokens)
		if _, ok := groups[key]; !ok {
			groups[key] = make(map[string]*ModelBreakdown)
		}
		b, ok := groups[key][r.Model]
		if !ok {
			b = &ModelBreakdown{Model: r.Model}
			groups[key][r.Model] = b
		}
		b.Input += r.InputTokens
		b.Output += r.OutputTokens
		b.CacheRead += r.CacheReadTokens
		b.CacheCreate += r.CacheCreationTokens
		b.Cost += cost
	}

	result := make(map[AggregateKey][]ModelBreakdown, len(groups))
	for key, models := range groups {
		list := make([]ModelBreakdown, 0, len(models))
		for _, b := range models {
			list = append(list, *b)
		}
		sort.Slice(list, func(i, j int) bool { return list[i].Cost > list[j].Cost })
		result[key] = list
	}
	return result
}

// AdaptiveModelRow aggregates usage and costs for one model selected by the
// adaptive router. MarketCost is what the same tokens would cost at the model's
// public API rate; AdaptiveCost is what they cost at the fixed adaptive rate.
type AdaptiveModelRow struct {
	Model        string
	Input        int64
	Output       int64
	CacheRead    int64
	CacheCreate  int64
	MarketCost   float64
	AdaptiveCost float64
	Saved        float64
	SavedPercent float64 // -1 means the model has no known public pricing
}

// AggregateAdaptiveByModel filters records to sessions that started with model
// "adaptive" and aggregates usage per routed model. It returns the per-model rows
// plus total market cost, total adaptive cost, and total savings.
func AggregateAdaptiveByModel(records []UsageRecord, prices map[string]ModelPrice) ([]AdaptiveModelRow, float64, float64, float64, error) {
	adaptiveRate, ok := prices[normalizeModelName("adaptive")]
	if !ok {
		return nil, 0, 0, 0, fmt.Errorf("adaptive rate not found in pricing table; run `devinusage pricing init` and add an \"adaptive\" entry")
	}

	groups := make(map[string]*AdaptiveModelRow)
	for _, r := range records {
		if normalizeModelName(r.SessionModel) != "adaptive" {
			continue
		}
		row, ok := groups[r.Model]
		if !ok {
			row = &AdaptiveModelRow{Model: r.Model}
			groups[r.Model] = row
		}
		row.Input += r.InputTokens
		row.Output += r.OutputTokens
		row.CacheRead += r.CacheReadTokens
		row.CacheCreate += r.CacheCreationTokens
		row.MarketCost += EstimateCost(prices, r.Model, r.InputTokens, r.OutputTokens, r.CacheReadTokens, r.CacheCreationTokens)
		row.AdaptiveCost += EstimateCostWithPrice(adaptiveRate, r.InputTokens, r.OutputTokens, r.CacheReadTokens, r.CacheCreationTokens)
	}

	result := make([]AdaptiveModelRow, 0, len(groups))
	var totalMarket, totalAdaptive, totalSaved float64
	for _, row := range groups {
		row.Saved = row.MarketCost - row.AdaptiveCost
		if row.MarketCost > 0 {
			row.SavedPercent = row.Saved / row.MarketCost
		} else {
			row.SavedPercent = -1
		}
		result = append(result, *row)
		if row.MarketCost > 0 {
			totalMarket += row.MarketCost
			totalAdaptive += row.AdaptiveCost
			totalSaved += row.Saved
		}
	}

	sort.Slice(result, func(i, j int) bool {
		if result[i].MarketCost != result[j].MarketCost {
			return result[i].MarketCost > result[j].MarketCost
		}
		return result[i].Model < result[j].Model
	})

	return result, totalMarket, totalAdaptive, totalSaved, nil
}

func RenderTable(w io.Writer, title string, aggregates []*Aggregate, showCache bool, showBreakdown bool, records []UsageRecord, prices map[string]ModelPrice, mode string, forcedWidth int) {
	fmt.Fprintf(w, "\n%s\n\n", title)

	if len(aggregates) == 0 {
		fmt.Fprintln(w, "No usage records found.")
		return
	}

	if showBreakdown {
		RenderBreakdown(w, aggregates, records, prices, mode, forcedWidth)
		return
	}

	width := EffectiveWidth(forcedWidth, 0)

	labelFlex := mode == "session"
	labelMin := 10
	labelMax := 60
	if mode != "session" {
		labelMax = 12
	}

	var rows [][]string
	for _, agg := range aggregates {
		models := strings.Join(agg.modelList(), ", ")
		row := []string{agg.Label, models, FormatTokens(agg.Input), FormatTokens(agg.Output)}
		if showCache {
			row = append(row, FormatTokens(agg.CacheRead))
		}
		row = append(row, fmt.Sprintf("$%.4f", agg.Cost))
		rows = append(rows, row)
	}

	var totalInput, totalOutput, totalCache int64
	var totalCost float64
	for _, agg := range aggregates {
		totalInput += agg.Input
		totalOutput += agg.Output
		totalCache += agg.CacheRead
		totalCost += agg.Cost
	}
	footer := []string{"TOTAL", "", FormatTokens(totalInput), FormatTokens(totalOutput)}
	if showCache {
		footer = append(footer, FormatTokens(totalCache))
	}
	footer = append(footer, fmt.Sprintf("$%.4f", totalCost))

	columns := []tableColumn{
		{header: "label", alignRight: false, flex: labelFlex, minWidth: labelMin, maxWidth: labelMax},
		{header: "models", alignRight: false, flex: true, minWidth: 12, maxWidth: 0},
		{header: "input", alignRight: true, flex: false, minWidth: 10, maxWidth: 12},
		{header: "output", alignRight: true, flex: false, minWidth: 10, maxWidth: 12},
	}
	if showCache {
		columns = append(columns, tableColumn{header: "cache_read", alignRight: true, flex: false, minWidth: 10, maxWidth: 12})
	}
	columns = append(columns, tableColumn{header: "cost", alignRight: true, flex: false, minWidth: 10, maxWidth: 12})

	renderBoxTable(w, columns, rows, footer, width, 0)
}

func RenderBreakdown(w io.Writer, aggregates []*Aggregate, records []UsageRecord, prices map[string]ModelPrice, mode string, forcedWidth int) {
	var keyFn func(UsageRecord) AggregateKey
	switch mode {
	case "daily":
		keyFn = func(r UsageRecord) AggregateKey { return AggregateKey(r.Timestamp.Format("2006-01-02")) }
	case "monthly":
		keyFn = func(r UsageRecord) AggregateKey { return AggregateKey(r.Timestamp.Format("2006-01")) }
	case "session":
		keyFn = func(r UsageRecord) AggregateKey { return AggregateKey(r.SessionID) }
	default:
		keyFn = func(r UsageRecord) AggregateKey { return AggregateKey(r.Timestamp.Format("2006-01-02")) }
	}
	breakdowns := BreakdownByModel(records, prices, keyFn)

	const indent = 2
	width := EffectiveWidth(forcedWidth, indent)

	for _, agg := range aggregates {
		fmt.Fprintf(w, "[%s] total cost $%.4f\n", agg.Label, agg.Cost)
		rows := breakdowns[agg.Key]
		if len(rows) == 0 {
			continue
		}
		var cells [][]string
		for _, b := range rows {
			cells = append(cells, []string{b.Model, FormatTokens(b.Input), FormatTokens(b.Output), FormatTokens(b.CacheRead), fmt.Sprintf("$%.4f", b.Cost)})
		}
		columns := []tableColumn{
			{header: "model", alignRight: false, flex: true, minWidth: 12, maxWidth: 0},
			{header: "input", alignRight: true, flex: false, minWidth: 10, maxWidth: 12},
			{header: "output", alignRight: true, flex: false, minWidth: 10, maxWidth: 12},
			{header: "cache_read", alignRight: true, flex: false, minWidth: 10, maxWidth: 12},
			{header: "cost", alignRight: true, flex: false, minWidth: 10, maxWidth: 12},
		}
		renderBoxTable(w, columns, cells, nil, width, indent)
		fmt.Fprintln(w)
	}
}

type tableColumn struct {
	header     string
	width      int
	alignRight bool
	flex       bool
	minWidth   int
	maxWidth   int
}

func EffectiveWidth(forcedWidth, indent int) int {
	width := forcedWidth
	if width <= 0 {
		width = TerminalWidth()
	}
	if width <= 0 {
		width = 120
	}
	width -= indent
	if width < 60 {
		width = 60
	}
	return width
}

func renderBoxTable(w io.Writer, columns []tableColumn, rows [][]string, footer []string, availableWidth, indent int) {
	columns = calculateColumnWidths(columns, rows, footer, availableWidth)

	printBoxBorder(w, columns, indent, "┌", "─", "┬", "┐")
	printBoxCells(w, columns, headersFromColumns(columns), indent)
	printBoxBorder(w, columns, indent, "├", "─", "┼", "┤")
	for _, row := range rows {
		printBoxCells(w, columns, row, indent)
	}
	if len(footer) > 0 {
		printBoxBorder(w, columns, indent, "├", "─", "┼", "┤")
		printBoxCells(w, columns, footer, indent)
	}
	printBoxBorder(w, columns, indent, "└", "─", "┴", "┘")
}

func headersFromColumns(columns []tableColumn) []string {
	headers := make([]string, len(columns))
	for i, c := range columns {
		headers[i] = c.header
	}
	return headers
}

func calculateColumnWidths(columns []tableColumn, rows [][]string, footer []string, availableWidth int) []tableColumn {
	// Each cell has 1 space of left/right padding, so total width = content + 2.
	for i := range columns {
		maxLen := len(columns[i].header)
		for _, row := range rows {
			if i < len(row) && len(row[i]) > maxLen {
				maxLen = len(row[i])
			}
		}
		if i < len(footer) && len(footer[i]) > maxLen {
			maxLen = len(footer[i])
		}
		width := maxLen + 2
		if width < columns[i].minWidth {
			width = columns[i].minWidth
		}
		if columns[i].maxWidth > 0 && width > columns[i].maxWidth {
			width = columns[i].maxWidth
		}
		columns[i].width = width
	}

	total := tableTotalWidth(columns)

	if total > availableWidth {
		excess := total - availableWidth
		for excess > 0 {
			shrunk := false
			for i := range columns {
				if columns[i].flex && columns[i].width > columns[i].minWidth {
					columns[i].width--
					excess--
					shrunk = true
					if excess <= 0 {
						break
					}
				}
			}
			if !shrunk {
				break
			}
		}
	} else if total < availableWidth {
		extra := availableWidth - total
		for extra > 0 {
			grown := false
			for i := range columns {
				if columns[i].flex && (columns[i].maxWidth == 0 || columns[i].width < columns[i].maxWidth) {
					columns[i].width++
					extra--
					grown = true
					if extra <= 0 {
						break
					}
				}
			}
			if !grown {
				break
			}
		}
	}

	return columns
}

func tableTotalWidth(columns []tableColumn) int {
	total := len(columns) + 1 // vertical borders: left + between columns + right
	for _, c := range columns {
		total += c.width
	}
	return total
}

func printBoxBorder(w io.Writer, columns []tableColumn, indent int, left, horizontal, sep, right string) {
	if indent > 0 {
		fmt.Fprint(w, strings.Repeat(" ", indent))
	}
	fmt.Fprint(w, left)
	for i, col := range columns {
		if i > 0 {
			fmt.Fprint(w, sep)
		}
		fmt.Fprint(w, strings.Repeat(horizontal, col.width))
	}
	fmt.Fprint(w, right)
	fmt.Fprintln(w)
}

func printBoxCells(w io.Writer, columns []tableColumn, cells []string, indent int) {
	if indent > 0 {
		fmt.Fprint(w, strings.Repeat(" ", indent))
	}
	fmt.Fprint(w, "│")
	for i, col := range columns {
		if i > 0 {
			fmt.Fprint(w, "│")
		}
		cell := ""
		if i < len(cells) {
			cell = cells[i]
		}
		contentWidth := col.width - 2
		if contentWidth < 1 {
			contentWidth = 1
		}
		s := truncate(cell, contentWidth)
		if col.alignRight {
			fmt.Fprintf(w, " %*s ", contentWidth, s)
		} else {
			fmt.Fprintf(w, " %-*s ", contentWidth, s)
		}
	}
	fmt.Fprint(w, "│")
	fmt.Fprintln(w)
}

func truncate(s string, maxLen int) string {
	if maxLen <= 3 {
		if len(s) > maxLen {
			return "..."
		}
		return s
	}
	if len(s) > maxLen {
		return s[:maxLen-3] + "..."
	}
	return s
}

func TerminalWidth() int {
	defaultWidth := 120

	cmd := exec.Command("stty", "size")
	cmd.Stdin = os.Stdin
	if out, err := cmd.Output(); err == nil {
		var rows, cols int
		if _, err := fmt.Sscanf(string(out), "%d %d", &rows, &cols); err == nil && cols > 0 {
			return cols
		}
	}

	cmd = exec.Command("tput", "cols")
	cmd.Stdin = os.Stdin
	if out, err := cmd.Output(); err == nil {
		if v, err := strconv.Atoi(strings.TrimSpace(string(out))); err == nil && v > 0 {
			return v
		}
	}

	return defaultWidth
}

func RenderJSON(w io.Writer, records []UsageRecord, prices map[string]ModelPrice, mode string) error {
	aggregates := AggregateBy(records, prices, mode)
	type jsonModel struct {
		Model       string  `json:"model"`
		Input       int64   `json:"input_tokens"`
		Output      int64   `json:"output_tokens"`
		CacheRead   int64   `json:"cache_read_tokens"`
		CacheCreate int64   `json:"cache_creation_tokens"`
		Cost        float64 `json:"cost_usd"`
	}
	type jsonAggregate struct {
		Key            string      `json:"key"`
		Label          string      `json:"label"`
		Models         []string    `json:"models"`
		Input          int64       `json:"input_tokens"`
		Output         int64       `json:"output_tokens"`
		CacheRead      int64       `json:"cache_read_tokens"`
		CacheCreate    int64       `json:"cache_creation_tokens"`
		Cost           float64     `json:"cost_usd"`
		LastActivityAt int64       `json:"last_activity_at"`
		Breakdown      []jsonModel `json:"breakdown,omitempty"`
	}

	var keyFn func(UsageRecord) AggregateKey
	switch mode {
	case "daily":
		keyFn = func(r UsageRecord) AggregateKey { return AggregateKey(r.Timestamp.Format("2006-01-02")) }
	case "monthly":
		keyFn = func(r UsageRecord) AggregateKey { return AggregateKey(r.Timestamp.Format("2006-01")) }
	case "session":
		keyFn = func(r UsageRecord) AggregateKey { return AggregateKey(r.SessionID) }
	default:
		keyFn = func(r UsageRecord) AggregateKey { return AggregateKey(r.Timestamp.Format("2006-01-02")) }
	}
	breakdowns := BreakdownByModel(records, prices, keyFn)

	lastActivity := make(map[AggregateKey]int64)
	for _, r := range records {
		key := keyFn(r)
		if r.Timestamp.Unix() > lastActivity[key] {
			lastActivity[key] = r.Timestamp.Unix()
		}
	}

	out := make([]jsonAggregate, 0, len(aggregates))
	for _, agg := range aggregates {
		ja := jsonAggregate{
			Key:            string(agg.Key),
			Label:          agg.Label,
			Models:         agg.modelList(),
			Input:          agg.Input,
			Output:         agg.Output,
			CacheRead:      agg.CacheRead,
			CacheCreate:    agg.CacheCreate,
			Cost:           agg.Cost,
			LastActivityAt: lastActivity[agg.Key],
		}
		for _, b := range breakdowns[agg.Key] {
			ja.Breakdown = append(ja.Breakdown, jsonModel{
				Model:       b.Model,
				Input:       b.Input,
				Output:      b.Output,
				CacheRead:   b.CacheRead,
				CacheCreate: b.CacheCreate,
				Cost:        b.Cost,
			})
		}
		out = append(out, ja)
	}

	enc := json.NewEncoder(w)
	enc.SetIndent("", "  ")
	return enc.Encode(out)
}

func FormatTokens(n int64) string {
	if n < 1000 {
		return fmt.Sprintf("%d", n)
	}
	if n < 1_000_000 {
		return fmt.Sprintf("%.1fk", float64(n)/1000)
	}
	return fmt.Sprintf("%.2fM", float64(n)/1_000_000)
}

func ParseDate(s string) (time.Time, error) {
	if s == "" {
		return time.Time{}, nil
	}
	return time.Parse("20060102", s)
}

// RenderAdaptiveTable prints an adaptive routing report showing which models the
// adaptive router selected and how much was saved versus paying public API rates.
func RenderAdaptiveTable(w io.Writer, records []UsageRecord, prices map[string]ModelPrice, showCache bool, forcedWidth int) {
	rows, totalMarket, totalAdaptive, totalSaved, err := AggregateAdaptiveByModel(records, prices)
	if err != nil {
		fmt.Fprintf(w, "error: %v\n", err)
		return
	}

	fmt.Fprintln(w, "\nDevin CLI Adaptive Routing Report\n")
	if len(rows) == 0 {
		fmt.Fprintln(w, "No adaptive usage records found.")
		return
	}

	width := EffectiveWidth(forcedWidth, 0)

	var cells [][]string
	var hasUnknown bool
	for _, r := range rows {
		row := []string{
			r.Model,
			FormatTokens(r.Input),
			FormatTokens(r.Output),
			fmt.Sprintf("$%.4f", r.MarketCost),
			fmt.Sprintf("$%.4f", r.AdaptiveCost),
			fmt.Sprintf("$%.4f", r.Saved),
		}
		if showCache {
			row = append(row, FormatTokens(r.CacheRead), FormatTokens(r.CacheCreate))
		}
		if r.SavedPercent >= 0 {
			row = append(row, fmt.Sprintf("%.1f%%", r.SavedPercent*100))
		} else {
			row = append(row, "n/a")
			hasUnknown = true
		}
		cells = append(cells, row)
	}

	footer := []string{
		"TOTAL",
		"",
		"",
		fmt.Sprintf("$%.4f", totalMarket),
		fmt.Sprintf("$%.4f", totalAdaptive),
		fmt.Sprintf("$%.4f", totalSaved),
	}
	if showCache {
		footer = append(footer, "", "")
	}
	if totalMarket > 0 {
		footer = append(footer, fmt.Sprintf("%.1f%%", totalSaved/totalMarket*100))
	} else {
		footer = append(footer, "n/a")
	}

	modelMaxWidth := 30
	if showCache {
		modelMaxWidth = 20
	}
	columns := []tableColumn{
		{header: "model", alignRight: false, flex: true, minWidth: 12, maxWidth: modelMaxWidth},
		{header: "input", alignRight: true, flex: false, minWidth: 10, maxWidth: 12},
		{header: "output", alignRight: true, flex: false, minWidth: 10, maxWidth: 12},
		{header: "market cost", alignRight: true, flex: false, minWidth: 13, maxWidth: 14},
		{header: "adaptive cost", alignRight: true, flex: false, minWidth: 13, maxWidth: 15},
		{header: "saved", alignRight: true, flex: false, minWidth: 13, maxWidth: 14},
	}
	if showCache {
		columns = append(columns,
			tableColumn{header: "cache_read", alignRight: true, flex: false, minWidth: 11, maxWidth: 12},
			tableColumn{header: "cache_cre", alignRight: true, flex: false, minWidth: 10, maxWidth: 12},
		)
	}
	columns = append(columns, tableColumn{header: "saved_pct", alignRight: true, flex: false, minWidth: 10, maxWidth: 12})

	renderBoxTable(w, columns, cells, footer, width, 0)

	fmt.Fprintln(w)
	fmt.Fprintf(w, "Adaptive rate: input $%.2f/M, output $%.2f/M, cache_read $%.2f/M, cache_creation $%.2f/M\n",
		prices[normalizeModelName("adaptive")].Input,
		prices[normalizeModelName("adaptive")].Output,
		prices[normalizeModelName("adaptive")].CacheRead,
		prices[normalizeModelName("adaptive")].CacheCreation,
	)
	if hasUnknown {
		fmt.Fprintln(w, "Models marked 'n/a' have no known public pricing and are excluded from the total savings calculation.")
	}
	fmt.Fprintln(w, "Use --width, --blocks, or --json for full model names and cache details.")
}

// RenderAdaptiveBlocks prints each routed model as a separate block, which avoids
// table-width issues on narrow terminals.
func RenderAdaptiveBlocks(w io.Writer, records []UsageRecord, prices map[string]ModelPrice) {
	rows, totalMarket, totalAdaptive, totalSaved, err := AggregateAdaptiveByModel(records, prices)
	if err != nil {
		fmt.Fprintf(w, "error: %v\n", err)
		return
	}

	fmt.Fprintln(w, "\nDevin CLI Adaptive Routing Report\n")
	if len(rows) == 0 {
		fmt.Fprintln(w, "No adaptive usage records found.")
		return
	}

	var hasUnknown bool
	for _, r := range rows {
		fmt.Fprintf(w, "%s\n", r.Model)
		fmt.Fprintf(w, "  input: %s, output: %s", FormatTokens(r.Input), FormatTokens(r.Output))
		if r.CacheRead > 0 || r.CacheCreate > 0 {
			fmt.Fprintf(w, ", cache_read: %s, cache_cre: %s", FormatTokens(r.CacheRead), FormatTokens(r.CacheCreate))
		}
		fmt.Fprintln(w)
		if r.SavedPercent >= 0 {
			fmt.Fprintf(w, "  market cost: $%.4f, adaptive cost: $%.4f, saved: $%.4f (%.1f%%)\n",
				r.MarketCost, r.AdaptiveCost, r.Saved, r.SavedPercent*100)
		} else {
			fmt.Fprintf(w, "  market cost: n/a, adaptive cost: $%.4f, saved: n/a\n", r.AdaptiveCost)
			hasUnknown = true
		}
		fmt.Fprintln(w)
	}

	fmt.Fprintf(w, "TOTAL: market cost $%.4f, adaptive cost $%.4f, saved $%.4f", totalMarket, totalAdaptive, totalSaved)
	if totalMarket > 0 {
		fmt.Fprintf(w, " (%.1f%%)", totalSaved/totalMarket*100)
	}
	fmt.Fprintln(w)
	fmt.Fprintf(w, "\nAdaptive rate: input $%.2f/M, output $%.2f/M, cache_read $%.2f/M, cache_creation $%.2f/M\n",
		prices[normalizeModelName("adaptive")].Input,
		prices[normalizeModelName("adaptive")].Output,
		prices[normalizeModelName("adaptive")].CacheRead,
		prices[normalizeModelName("adaptive")].CacheCreation,
	)
	if hasUnknown {
		fmt.Fprintln(w, "Models marked 'n/a' have no known public pricing and are excluded from the total savings calculation.")
	}
}

// RenderAdaptiveJSON outputs the adaptive routing report as JSON.
func RenderAdaptiveJSON(w io.Writer, records []UsageRecord, prices map[string]ModelPrice) error {
	rows, totalMarket, totalAdaptive, totalSaved, err := AggregateAdaptiveByModel(records, prices)
	if err != nil {
		return err
	}

	type jsonRow struct {
		Model        string  `json:"model"`
		Input        int64   `json:"input_tokens"`
		Output       int64   `json:"output_tokens"`
		CacheRead    int64   `json:"cache_read_tokens"`
		CacheCreate  int64   `json:"cache_creation_tokens"`
		MarketCost   float64 `json:"market_cost_usd"`
		AdaptiveCost float64 `json:"adaptive_cost_usd"`
		Saved        float64 `json:"saved_usd"`
		SavedPercent float64 `json:"saved_percent"`
	}

	outRows := make([]jsonRow, 0, len(rows))
	for _, r := range rows {
		outRows = append(outRows, jsonRow{
			Model:        r.Model,
			Input:        r.Input,
			Output:       r.Output,
			CacheRead:    r.CacheRead,
			CacheCreate:  r.CacheCreate,
			MarketCost:   r.MarketCost,
			AdaptiveCost: r.AdaptiveCost,
			Saved:        r.Saved,
			SavedPercent: r.SavedPercent,
		})
	}

	out := struct {
		Rows         []jsonRow `json:"rows"`
		TotalMarket  float64   `json:"total_market_cost_usd"`
		TotalAdaptive float64  `json:"total_adaptive_cost_usd"`
		TotalSaved   float64   `json:"total_saved_usd"`
		TotalSavedPercent float64 `json:"total_saved_percent"`
	}{
		Rows:         outRows,
		TotalMarket:  totalMarket,
		TotalAdaptive: totalAdaptive,
		TotalSaved:   totalSaved,
	}
	if totalMarket > 0 {
		out.TotalSavedPercent = totalSaved / totalMarket
	}

	enc := json.NewEncoder(w)
	enc.SetIndent("", "  ")
	return enc.Encode(out)
}
