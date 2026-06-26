package main

import (
	"bytes"
	"fmt"
	"image"
	"image/color"
	"image/png"
	"time"

	"fyne.io/fyne/v2"
	"fyne.io/fyne/v2/app"
	"fyne.io/fyne/v2/container"
	"fyne.io/fyne/v2/driver/desktop"
	"fyne.io/fyne/v2/widget"
	"github.com/ayu/devinusage/internal/devinusage"
)

var (
	uiTodayCost     *widget.Label
	uiTodayTokens   *widget.Label
	uiMonthCost     *widget.Label
	uiMonthTokens   *widget.Label
	uiSessionCost   *widget.Label
	uiSessionTokens *widget.Label
)

func main() {
	a := app.New()
	w := a.NewWindow("DevinBar")
	w.SetContent(buildUI())
	w.Resize(fyne.NewSize(360, 480))
	w.CenterOnScreen()
	w.SetCloseIntercept(func() {
		w.Hide()
	})

	if desk, ok := a.(desktop.App); ok {
		icon := fyne.NewStaticResource("icon", generateIcon())
		w.SetIcon(icon)
		desk.SetSystemTrayIcon(icon)
		menu := fyne.NewMenu("DevinBar",
			fyne.NewMenuItem("Open Dashboard", func() {
				w.Show()
				w.RequestFocus()
			}),
			fyne.NewMenuItem("Refresh", func() {
				refresh()
			}),
			fyne.NewMenuItemSeparator(),
			fyne.NewMenuItem("Quit", func() {
				a.Quit()
			}),
		)
		desk.SetSystemTrayMenu(menu)
	}

	refresh()

	go func() {
		ticker := time.NewTicker(30 * time.Second)
		defer ticker.Stop()
		for range ticker.C {
			refresh()
		}
	}()

	w.ShowAndRun()
}

func buildUI() fyne.CanvasObject {
	uiTodayCost = widget.NewLabel("$0.00")
	uiTodayCost.TextStyle = fyne.TextStyle{Bold: true}
	uiTodayCost.Alignment = fyne.TextAlignCenter

	uiTodayTokens = widget.NewLabel("0 in / 0 out / 0 cache")
	uiTodayTokens.Alignment = fyne.TextAlignCenter

	uiMonthCost = widget.NewLabel("$0.00")
	uiMonthCost.TextStyle = fyne.TextStyle{Bold: true}
	uiMonthCost.Alignment = fyne.TextAlignCenter

	uiMonthTokens = widget.NewLabel("0 in / 0 out / 0 cache")
	uiMonthTokens.Alignment = fyne.TextAlignCenter

	uiSessionCost = widget.NewLabel("$0.00")
	uiSessionCost.TextStyle = fyne.TextStyle{Bold: true}
	uiSessionCost.Alignment = fyne.TextAlignCenter

	uiSessionTokens = widget.NewLabel("0 in / 0 out / 0 cache")
	uiSessionTokens.Alignment = fyne.TextAlignCenter

	todayCard := widget.NewCard("Today", "",
		container.NewVBox(
			uiTodayCost,
			uiTodayTokens,
		),
	)

	monthCard := widget.NewCard("This Month", "",
		container.NewVBox(
			uiMonthCost,
			uiMonthTokens,
		),
	)

	sessionCard := widget.NewCard("Current Session", "",
		container.NewVBox(
			uiSessionCost,
			uiSessionTokens,
		),
	)

	refreshBtn := widget.NewButton("Refresh Now", func() {
		refresh()
	})
	refreshBtn.Importance = widget.HighImportance

	return container.NewVBox(
		widget.NewLabelWithStyle("Devin Usage", fyne.TextAlignCenter, fyne.TextStyle{Bold: true}),
		widget.NewSeparator(),
		todayCard,
		monthCard,
		sessionCard,
		refreshBtn,
	)
}

func refresh() {
	prices, err := devinusage.LoadPricing("")
	if err != nil {
		prices = nil
	}

	now := time.Now()
	todayStart := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, time.Local)
	monthStart := time.Date(now.Year(), now.Month(), 1, 0, 0, 0, 0, time.Local)

	todayRecords, _ := devinusage.ReadUsageRecords("", todayStart, now)
	monthRecords, _ := devinusage.ReadUsageRecords("", monthStart, now)

	todayAgg := sumAggregates(devinusage.AggregateBy(todayRecords, prices, "daily"))
	monthAgg := sumAggregates(devinusage.AggregateBy(monthRecords, prices, "monthly"))

	uiTodayCost.SetText(fmt.Sprintf("$%.2f", todayAgg.Cost))
	uiTodayTokens.SetText(fmt.Sprintf("%s in / %s out / %s cache",
		devinusage.FormatTokens(todayAgg.Input),
		devinusage.FormatTokens(todayAgg.Output),
		devinusage.FormatTokens(todayAgg.CacheRead)))

	uiMonthCost.SetText(fmt.Sprintf("$%.2f", monthAgg.Cost))
	uiMonthTokens.SetText(fmt.Sprintf("%s in / %s out / %s cache",
		devinusage.FormatTokens(monthAgg.Input),
		devinusage.FormatTokens(monthAgg.Output),
		devinusage.FormatTokens(monthAgg.CacheRead)))

	if current := currentSession(todayRecords); current != "" {
		sessionRecords := filterBySession(todayRecords, current)
		sessionAgg := sumAggregates(devinusage.AggregateBy(sessionRecords, prices, "session"))
		uiSessionCost.SetText(fmt.Sprintf("$%.2f", sessionAgg.Cost))
		uiSessionTokens.SetText(fmt.Sprintf("%s in / %s out / %s cache",
			devinusage.FormatTokens(sessionAgg.Input),
			devinusage.FormatTokens(sessionAgg.Output),
			devinusage.FormatTokens(sessionAgg.CacheRead)))
	} else {
		uiSessionCost.SetText("—")
		uiSessionTokens.SetText("no active session today")
	}
}

func sumAggregates(aggs []*devinusage.Aggregate) *devinusage.Aggregate {
	out := &devinusage.Aggregate{}
	for _, a := range aggs {
		out.Input += a.Input
		out.Output += a.Output
		out.CacheRead += a.CacheRead
		out.CacheCreate += a.CacheCreate
		out.Cost += a.Cost
	}
	return out
}

func currentSession(records []devinusage.UsageRecord) string {
	if len(records) == 0 {
		return ""
	}
	latest := records[0]
	for _, r := range records {
		if r.Timestamp.After(latest.Timestamp) {
			latest = r
		}
	}
	return latest.SessionID
}

func filterBySession(records []devinusage.UsageRecord, sessionID string) []devinusage.UsageRecord {
	var out []devinusage.UsageRecord
	for _, r := range records {
		if r.SessionID == sessionID {
			out = append(out, r)
		}
	}
	return out
}

func generateIcon() []byte {
	img := image.NewRGBA(image.Rect(0, 0, 16, 16))
	c := color.RGBA{0, 0, 0, 255}
	for y := 0; y < 16; y++ {
		for x := 0; x < 16; x++ {
			img.Set(x, y, c)
		}
	}
	var buf bytes.Buffer
	png.Encode(&buf, img)
	return buf.Bytes()
}
