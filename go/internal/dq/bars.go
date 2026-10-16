// Package dq holds blocking data-quality rules for unadjusted daily bars.
package dq

import (
	"errors"
	"fmt"
	"math"
	"time"
)

type Bar struct {
	Symbol string  `json:"symbol"`
	Date   string  `json:"trade_date"`
	Open   float64 `json:"open"`
	High   float64 `json:"high"`
	Low    float64 `json:"low"`
	Close  float64 `json:"close"`
	Volume float64 `json:"volume"`
}

func Validate(rows []Bar) error {
	if len(rows) == 0 {
		return errors.New("no bars")
	}
	seen := map[string]bool{}
	for i, b := range rows {
		if b.Symbol == "" {
			return fmt.Errorf("row %d: no symbol", i)
		}
		day, err := time.Parse("2006-01-02", b.Date)
		if err != nil || day.Format("2006-01-02") != b.Date {
			return fmt.Errorf("row %d: invalid session date", i)
		}
		key := b.Symbol + ":" + b.Date
		if seen[key] {
			return fmt.Errorf("row %d: duplicate %s", i, key)
		}
		seen[key] = true
		for _, item := range []struct {
			name  string
			price float64
		}{{"open", b.Open}, {"high", b.High}, {"low", b.Low}, {"close", b.Close}} {
			if item.price <= 0 || math.IsNaN(item.price) || math.IsInf(item.price, 0) {
				return fmt.Errorf("row %d date %s: %s price is nonpositive or nonfinite", i, b.Date, item.name)
			}
		}
		for _, check := range []struct {
			bad    bool
			reason string
		}{
			{b.High < b.Low, "high below low"},
			{b.High < b.Open, "high below open"},
			{b.High < b.Close, "high below close"},
			{b.Low > b.Open, "low above open"},
			{b.Low > b.Close, "low above close"},
		} {
			if check.bad {
				return fmt.Errorf("row %d date %s: %s", i, b.Date, check.reason)
			}
		}
		if b.Volume < 0 || math.IsNaN(b.Volume) || math.IsInf(b.Volume, 0) {
			return fmt.Errorf("row %d date %s: negative or nonfinite volume", i, b.Date)
		}
	}
	return nil
}

func StaleShare(latestBySymbol map[string]time.Time, expected time.Time, threshold float64) (bool, float64, error) {
	if len(latestBySymbol) == 0 || expected.IsZero() || threshold < 0 || threshold > 1 || math.IsNaN(threshold) {
		return true, 1, errors.New("invalid staleness sample")
	}
	stale := 0
	for _, last := range latestBySymbol {
		if last.Before(expected) {
			stale++
		}
	}
	fraction := float64(stale) / float64(len(latestBySymbol))
	return fraction > threshold, fraction, nil
}
