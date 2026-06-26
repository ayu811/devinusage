package main

import (
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"time"

	"github.com/ayu/devinusage/internal/devinusage"
)

const usage = `devinusage — analyze Devin CLI token usage and costs from local data.

Commands:
  daily      Daily usage report (default)
  monthly    Monthly usage report
  session    Per-session usage report
  pricing    Manage model pricing configuration

Examples:
  devinusage
  devinusage daily --since 20250601 --until 20250630
  devinusage monthly --breakdown
  devinusage session --json
  devinusage pricing init > pricing.json

Use devinusage <command> --help for command-specific flags.
`

func main() {
	if len(os.Args) < 2 {
		runDaily([]string{})
		return
	}

	switch os.Args[1] {
	case "daily":
		runDaily(os.Args[2:])
	case "monthly":
		runMonthly(os.Args[2:])
	case "session":
		runSession(os.Args[2:])
	case "pricing":
		runPricing(os.Args[2:])
	case "help", "--help", "-h":
		fmt.Fprint(os.Stdout, usage)
	default:
		// Default behavior: treat the whole argument list as daily flags.
		// This lets `devinusage --since 20250601` work without a subcommand.
		runDaily(os.Args[1:])
	}
}

type reportFlags struct {
	DBPath      string
	PricingPath string
	Since       string
	Until       string
	JSON        bool
	Breakdown   bool
	NoCache     bool
	Width       int
}

func reportFlagSet(name string) (*flag.FlagSet, *reportFlags) {
	fs := flag.NewFlagSet(name, flag.ExitOnError)
	f := &reportFlags{}
	fs.StringVar(&f.DBPath, "db", "", "Path to Devin CLI sessions.db (default: ~/.local/share/devin/cli/sessions.db)")
	fs.StringVar(&f.PricingPath, "pricing", "", "Path to JSON pricing file (default: ./pricing.json if present, otherwise built-in estimates)")
	fs.StringVar(&f.Since, "since", "", "Include records on or after YYYYMMDD")
	fs.StringVar(&f.Until, "until", "", "Include records on or before YYYYMMDD")
	fs.BoolVar(&f.JSON, "json", false, "Output JSON instead of a table")
	fs.BoolVar(&f.Breakdown, "breakdown", false, "Show per-model breakdown")
	fs.BoolVar(&f.NoCache, "no-cache", false, "Hide cache-read column")
	fs.IntVar(&f.Width, "width", 0, "Force table width in characters (default: auto-detect terminal width)")
	return fs, f
}

func runReport(name, mode string, args []string) {
	fs, f := reportFlagSet(name)
	if err := fs.Parse(args); err != nil {
		fmt.Fprintf(os.Stderr, "error: %v\n", err)
		os.Exit(1)
	}

	since, err := devinusage.ParseDate(f.Since)
	if err != nil {
		fmt.Fprintf(os.Stderr, "error: invalid --since: %v\n", err)
		os.Exit(1)
	}
	until, err := devinusage.ParseDate(f.Until)
	if err != nil {
		fmt.Fprintf(os.Stderr, "error: invalid --until: %v\n", err)
		os.Exit(1)
	}
	if !until.IsZero() {
		until = until.Add(24*time.Hour - time.Second)
	}

	records, err := devinusage.ReadUsageRecords(f.DBPath, since, until)
	if err != nil {
		fmt.Fprintf(os.Stderr, "error: %v\n", err)
		os.Exit(1)
	}

	prices, err := devinusage.LoadPricing(f.PricingPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "error: %v\n", err)
		os.Exit(1)
	}

	if f.JSON {
		if err := devinusage.RenderJSON(os.Stdout, records, prices, mode); err != nil {
			fmt.Fprintf(os.Stderr, "error: %v\n", err)
			os.Exit(1)
		}
		return
	}

	aggregates := devinusage.AggregateBy(records, prices, mode)
	var title string
	switch mode {
	case "daily":
		title = "Devin CLI Daily Usage Report"
	case "monthly":
		title = "Devin CLI Monthly Usage Report"
	case "session":
		title = "Devin CLI Session Usage Report"
	}
	devinusage.RenderTable(os.Stdout, title, aggregates, !f.NoCache, f.Breakdown, records, prices, mode, f.Width)

	unknown := collectUnknownModels(records, prices)
	if len(unknown) > 0 {
		fmt.Fprintf(os.Stdout, "\nUnknown models (priced at $0): %s\n", stringsJoin(unknown, ", "))
		fmt.Fprintf(os.Stdout, "Configure prices with `devinusage pricing init` and `--pricing`.\n")
	}
}

func runDaily(args []string) {
	runReport("daily", "daily", args)
}

func runMonthly(args []string) {
	runReport("monthly", "monthly", args)
}

func runSession(args []string) {
	runReport("session", "session", args)
}

func runPricing(args []string) {
	// Manual subcommand parsing because flag.Parse stops at the first
	// positional argument, which breaks `pricing init <path>`.
	if len(args) == 0 || (len(args) == 1 && args[0] == "show") {
		fmt.Fprint(os.Stdout, devinusage.DumpDefaultPricing())
		return
	}

	if args[0] == "init" {
		path := "pricing.json"
		if len(args) >= 2 {
			path = args[1]
		}
		dir := filepath.Dir(path)
		if dir != "" && dir != "." {
			if err := os.MkdirAll(dir, 0o755); err != nil {
				fmt.Fprintf(os.Stderr, "error: create directory: %v\n", err)
				os.Exit(1)
			}
		}
		if err := os.WriteFile(path, []byte(devinusage.DumpDefaultPricing()), 0o644); err != nil {
			fmt.Fprintf(os.Stderr, "error: write pricing file: %v\n", err)
			os.Exit(1)
		}
		fmt.Fprintf(os.Stdout, "Pricing template written to %s\n", path)
		return
	}

	fmt.Fprintf(os.Stderr, "unknown pricing subcommand: %s\n\nUsage: devinusage pricing [show|init [path]]\n", args[0])
	os.Exit(1)
}

func collectUnknownModels(records []devinusage.UsageRecord, prices map[string]devinusage.ModelPrice) []string {
	seen := make(map[string]bool)
	var unknown []string
	for _, r := range records {
		if !devinusage.IsKnownModel(prices, r.Model) && !seen[r.Model] {
			seen[r.Model] = true
			unknown = append(unknown, r.Model)
		}
	}
	return unknown
}

func stringsJoin(s []string, sep string) string {
	out := ""
	for i, v := range s {
		if i > 0 {
			out += sep
		}
		out += v
	}
	return out
}
