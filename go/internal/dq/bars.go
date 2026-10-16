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
		for _, price := range []float64{b.Open, b.High, b.Low, b.Close} {
			if price <= 0 || math.IsNaN(price) || math.IsInf(price, 0) {
				return fmt.Errorf("row %d: invalid price", i)
			}
		}
		if b.High < b.Low || b.High < b.Open || b.High < b.Close || b.Low > b.Open || b.Low > b.Close {
			return fmt.Errorf("row %d: inconsistent OHLC", i)
		}
		if b.Volume < 0 || math.IsNaN(b.Volume) || math.IsInf(b.Volume, 0) {
			return fmt.Errorf("row %d: invalid volume", i)
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
