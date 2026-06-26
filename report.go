package main

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

func aggregateBy(records []UsageRecord, prices map[string]ModelPrice, mode string) []*Aggregate {
	buckets := make(map[AggregateKey]*Aggregate)
	for _, r := range records {
		cost := estimateCost(prices, r.Model, r.InputTokens, r.OutputTokens, r.CacheReadTokens, r.CacheCreationTokens)
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
			label = sessionLabel(r)
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

func sessionLabel(r UsageRecord) string {
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

func breakdownByModel(records []UsageRecord, prices map[string]ModelPrice, keyFn func(UsageRecord) AggregateKey) map[AggregateKey][]ModelBreakdown {
	groups := make(map[AggregateKey]map[string]*ModelBreakdown)
	for _, r := range records {
		key := keyFn(r)
		cost := estimateCost(prices, r.Model, r.InputTokens, r.OutputTokens, r.CacheReadTokens, r.CacheCreationTokens)
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

func renderTable(w io.Writer, title string, aggregates []*Aggregate, showCache bool, showBreakdown bool, records []UsageRecord, prices map[string]ModelPrice, mode string, forcedWidth int) {
	fmt.Fprintf(w, "\n%s\n\n", title)

	if len(aggregates) == 0 {
		fmt.Fprintln(w, "No usage records found.")
		return
	}

	if showBreakdown {
		renderBreakdown(w, aggregates, records, prices, mode, forcedWidth)
		return
	}

	width := effectiveWidth(forcedWidth, 0)

	labelFlex := mode == "session"
	labelMin := 10
	labelMax := 60
	if mode != "session" {
		labelMax = 12
	}

	var rows [][]string
	for _, agg := range aggregates {
		models := strings.Join(agg.modelList(), ", ")
		row := []string{agg.Label, models, formatTokens(agg.Input), formatTokens(agg.Output)}
		if showCache {
			row = append(row, formatTokens(agg.CacheRead))
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
	footer := []string{"TOTAL", "", formatTokens(totalInput), formatTokens(totalOutput)}
	if showCache {
		footer = append(footer, formatTokens(totalCache))
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

func renderBreakdown(w io.Writer, aggregates []*Aggregate, records []UsageRecord, prices map[string]ModelPrice, mode string, forcedWidth int) {
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
	breakdowns := breakdownByModel(records, prices, keyFn)

	const indent = 2
	width := effectiveWidth(forcedWidth, indent)

	for _, agg := range aggregates {
		fmt.Fprintf(w, "[%s] total cost $%.4f\n", agg.Label, agg.Cost)
		rows := breakdowns[agg.Key]
		if len(rows) == 0 {
			continue
		}
		var cells [][]string
		for _, b := range rows {
			cells = append(cells, []string{b.Model, formatTokens(b.Input), formatTokens(b.Output), formatTokens(b.CacheRead), fmt.Sprintf("$%.4f", b.Cost)})
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

func effectiveWidth(forcedWidth, indent int) int {
	width := forcedWidth
	if width <= 0 {
		width = terminalWidth()
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

func terminalWidth() int {
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

func renderJSON(w io.Writer, records []UsageRecord, prices map[string]ModelPrice, mode string) error {
	aggregates := aggregateBy(records, prices, mode)
	type jsonModel struct {
		Model       string  `json:"model"`
		Input       int64   `json:"input_tokens"`
		Output      int64   `json:"output_tokens"`
		CacheRead   int64   `json:"cache_read_tokens"`
		CacheCreate int64   `json:"cache_creation_tokens"`
		Cost        float64 `json:"cost_usd"`
	}
	type jsonAggregate struct {
		Key         string      `json:"key"`
		Label       string      `json:"label"`
		Models      []string    `json:"models"`
		Input       int64       `json:"input_tokens"`
		Output      int64       `json:"output_tokens"`
		CacheRead   int64       `json:"cache_read_tokens"`
		CacheCreate int64       `json:"cache_creation_tokens"`
		Cost        float64     `json:"cost_usd"`
		Breakdown   []jsonModel `json:"breakdown,omitempty"`
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
	breakdowns := breakdownByModel(records, prices, keyFn)

	out := make([]jsonAggregate, 0, len(aggregates))
	for _, agg := range aggregates {
		ja := jsonAggregate{
			Key:         string(agg.Key),
			Label:       agg.Label,
			Models:      agg.modelList(),
			Input:       agg.Input,
			Output:      agg.Output,
			CacheRead:   agg.CacheRead,
			CacheCreate: agg.CacheCreate,
			Cost:        agg.Cost,
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

func formatTokens(n int64) string {
	if n < 1000 {
		return fmt.Sprintf("%d", n)
	}
	if n < 1_000_000 {
		return fmt.Sprintf("%.1fk", float64(n)/1000)
	}
	return fmt.Sprintf("%.2fM", float64(n)/1_000_000)
}

func parseDate(s string) (time.Time, error) {
	if s == "" {
		return time.Time{}, nil
	}
	return time.Parse("20060102", s)
}
