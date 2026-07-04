package devinusage

import (
	"encoding/json"
	"fmt"
	"os"
	"strings"
)

const DefaultPricingFile = "pricing.json"

// ModelPrice stores cost per 1 million tokens (USD).
type ModelPrice struct {
	Input         float64 `json:"input"`
	Output        float64 `json:"output"`
	CacheRead     float64 `json:"cache_read"`
	CacheCreation float64 `json:"cache_creation"`
}

// defaultPricing is the built-in pricing table. These are **estimates** based on
// public API pricing for the underlying model providers. Devin CLI may apply
// different rates, credits, or internal routing. Use `devinusage pricing init` to
// generate a JSON file you can edit, then pass it with `--pricing`.
//
// Verified against public pricing pages as of 2026-07-04:
//   - Anthropic Claude: https://platform.claude.com/docs/en/about-claude/pricing
//   - Moonshot Kimi: https://api.moonshot.ai, https://developer.puter.com/tutorials/kimi-api-pricing
//   - Zhipu GLM / Z.ai: https://docs.z.ai, https://tokencost.app/models/glm-5-2
//   - OpenAI GPT / o-series: https://developers.openai.com/api/docs/models
//   - Devin adaptive: https://docs.devin.ai/cli/adaptive
var defaultPricing = map[string]ModelPrice{
	// Anthropic Claude (source: platform.claude.com/docs, 2026-07)
	// Opus 4.7/4.6: $5/$25; cache read 10% of input; 5m cache write 1.25x input.
	"claude-opus-4-7":        {Input: 5.00, Output: 25.00, CacheRead: 0.50, CacheCreation: 6.25},
	"claude-opus-4-7-low":    {Input: 5.00, Output: 25.00, CacheRead: 0.50, CacheCreation: 6.25},
	"claude-opus-4-7-medium": {Input: 5.00, Output: 25.00, CacheRead: 0.50, CacheCreation: 6.25},
	"claude-sonnet-4-6":      {Input: 3.00, Output: 15.00, CacheRead: 0.30, CacheCreation: 3.75},

	// Moonshot Kimi (source: platform.kimi.ai, 2026-07)
	"kimi-k2-5": {Input: 0.60, Output: 3.00, CacheRead: 0.10, CacheCreation: 0.60},
	"kimi-k2-6": {Input: 0.95, Output: 4.00, CacheRead: 0.16, CacheCreation: 0.95},
	"kimi-k2-7": {Input: 0.95, Output: 4.00, CacheRead: 0.19, CacheCreation: 0.95},

	// Zhipu GLM / Z.ai (source: docs.z.ai, tokencost.app, 2026-07)
	"glm-5-2": {Input: 1.40, Output: 4.40, CacheRead: 0.26, CacheCreation: 1.40},

	// Google Gemini (source: ai.google.dev, 2026-07)
	// MODEL_GOOGLE_GEMINI_3_0_FLASH_LOW is treated as the low/flash-lite tier.
	"model_google_gemini_3_0_flash_low": {Input: 0.25, Output: 1.50, CacheRead: 0.03, CacheCreation: 0.25},

	// OpenAI GPT / o-series (source: developers.openai.com, 2026-07)
	"gpt-4o":           {Input: 2.50, Output: 10.00, CacheRead: 1.25, CacheCreation: 2.50},
	"gpt-4o-mini":      {Input: 0.15, Output: 0.60, CacheRead: 0.075, CacheCreation: 0.15},
	"gpt-5.2":          {Input: 1.75, Output: 14.00, CacheRead: 0.175, CacheCreation: 1.75},
	"model_gpt_5_2_low": {Input: 1.75, Output: 14.00, CacheRead: 0.175, CacheCreation: 1.75},
	"o3":               {Input: 2.00, Output: 8.00, CacheRead: 0.50, CacheCreation: 2.00},
	"o4-mini":          {Input: 1.10, Output: 4.40, CacheRead: 0.275, CacheCreation: 1.10},

	// Devin CLI / Cognition internal models (source: docs.devin.ai/cli/adaptive, 2026-07)
	//
	// Adaptive self-serve pricing is a fixed per-token rate that applies regardless of
	// the underlying model. As of 2026-07-04, it is an introductory promotional rate
	// through 2026-07-07; after that date the rate may change.
	//
	// Cognition routing/SWE models are not publicly priced, so the adaptive rate is used
	// as a conservative proxy for market-rate comparisons.
	"adaptive":           {Input: 0.50, Output: 2.00, CacheRead: 0.10, CacheCreation: 0.50},
	"swe-1-6":            {Input: 0.50, Output: 2.00, CacheRead: 0.10, CacheCreation: 0.50},
	"swe-1-6-fast":       {Input: 0.50, Output: 2.00, CacheRead: 0.10, CacheCreation: 0.50},
	"model_swe_1_5":      {Input: 0.50, Output: 2.00, CacheRead: 0.10, CacheCreation: 0.50},
	"model_swe_1_5_slow": {Input: 0.50, Output: 2.00, CacheRead: 0.10, CacheCreation: 0.50},
	"model_private_11":   {Input: 0.50, Output: 2.00, CacheRead: 0.10, CacheCreation: 0.50},
	"compactor":          {Input: 0.50, Output: 2.00, CacheRead: 0.10, CacheCreation: 0.50},
	"summarizer":         {Input: 0.50, Output: 2.00, CacheRead: 0.10, CacheCreation: 0.50},
	"swe-check":          {Input: 0.50, Output: 2.00, CacheRead: 0.10, CacheCreation: 0.50},
}

func normalizeModelName(model string) string {
	return strings.ToLower(strings.TrimSpace(model))
}

func priceForModel(prices map[string]ModelPrice, model string) ModelPrice {
	normalized := normalizeModelName(model)
	if p, ok := prices[normalized]; ok {
		return p
	}
	// Prefix match for variants like claude-opus-4-7-low.
	for key, p := range prices {
		if strings.HasPrefix(normalized, key) || strings.HasPrefix(key, normalized) {
			return p
		}
	}
	return ModelPrice{}
}

func EstimateCostWithPrice(price ModelPrice, input, output, cacheRead, cacheCreation int64) float64 {
	return float64(input)/1e6*price.Input +
		float64(output)/1e6*price.Output +
		float64(cacheRead)/1e6*price.CacheRead +
		float64(cacheCreation)/1e6*price.CacheCreation
}

func EstimateCost(prices map[string]ModelPrice, model string, input, output, cacheRead, cacheCreation int64) float64 {
	return EstimateCostWithPrice(priceForModel(prices, model), input, output, cacheRead, cacheCreation)
}

func IsKnownModel(prices map[string]ModelPrice, model string) bool {
	return priceForModel(prices, model) != (ModelPrice{})
}

func LoadPricing(path string) (map[string]ModelPrice, error) {
	if path == "" {
		// Auto-load a local pricing.json if it exists, otherwise fall back to
		// built-in estimates. This keeps the tool self-contained in one directory.
		if _, err := os.Stat(DefaultPricingFile); err == nil {
			path = DefaultPricingFile
		} else {
			return copyPricing(defaultPricing), nil
		}
	}
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("read pricing file: %w", err)
	}
	var raw map[string]json.RawMessage
	if err := json.Unmarshal(data, &raw); err != nil {
		return nil, fmt.Errorf("parse pricing file: %w", err)
	}

	prices := make(map[string]ModelPrice, len(raw))
	for key, value := range raw {
		// Skip comment/annotation keys starting with underscore.
		if strings.HasPrefix(key, "_") {
			continue
		}
		normalized := normalizeModelName(key)

		var single float64
		if err := json.Unmarshal(value, &single); err == nil {
			prices[normalized] = ModelPrice{Input: single, Output: single, CacheRead: 0, CacheCreation: 0}
			continue
		}

		var p ModelPrice
		if err := json.Unmarshal(value, &p); err != nil {
			return nil, fmt.Errorf("invalid price entry for %s: %w", key, err)
		}
		prices[normalized] = p
	}
	return prices, nil
}

func copyPricing(src map[string]ModelPrice) map[string]ModelPrice {
	out := make(map[string]ModelPrice, len(src))
	for k, v := range src {
		out[k] = v
	}
	return out
}

func DumpDefaultPricing() string {
	type entry struct {
		Input         float64 `json:"input"`
		Output        float64 `json:"output"`
		CacheRead     float64 `json:"cache_read"`
		CacheCreation float64 `json:"cache_creation"`
	}
	data := map[string]interface{}{
		"_note":            "Prices are per 1 million tokens. Adjust to match your actual Devin CLI / model provider pricing.",
		"_unknown_models": "Models not listed below are priced at $0 and marked as 'unknown' in reports.",
	}
	for name, price := range defaultPricing {
		data[name] = entry(price)
	}
	b, _ := json.MarshalIndent(data, "", "  ")
	return string(b) + "\n"
}
