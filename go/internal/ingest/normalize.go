// Package ingest converts verified vendor frames to canonical, auditable data.
// No route calls are made here; the live.Gateway owns all quota-consuming calls.
package ingest

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math"
	"strconv"
	"strings"
	"time"

	"github.com/Kashumir-Kaiser/VN-Signal/go/internal/dq"
)

var ErrInvalidFrame = errors.New("invalid vendor frame: refuse ingest")

// BarsResult is strictly validated before writing to PostgreSQL. Invalid or
// unknown schemas are quarantined; no prices are synthesized or forward-filled.
type BarsResult struct {
	Symbol    string   `json:"symbol"`
	Count     int      `json:"count"`
	FirstDate string   `json:"first_date"`
	LastDate  string   `json:"last_date"`
	Rows      []dq.Bar `json:"rows"`
}

type frame struct {
	Columns    []string                     `json:"columns"`
	Count      int                          `json:"count"`
	Rows       []map[string]json.RawMessage `json:"rows"`
	Attributes json.RawMessage              `json:"attributes"`
}

// NormalizeBars accepts the 'data' object of a successful Python worker frame.
// Schema is checked against exact column names, not positional assumptions.
func NormalizeBars(symbol string, raw []byte) (BarsResult, error) {
	var result BarsResult
	symbol = strings.ToUpper(strings.TrimSpace(symbol))
	if len(symbol) < 1 || len(symbol) > 12 {
		return result, fmt.Errorf("%w: invalid symbol", ErrInvalidFrame)
	}
	for _, ch := range symbol {
		if !(ch >= 'A' && ch <= 'Z' || ch >= '0' && ch <= '9') {
			return result, fmt.Errorf("%w: invalid symbol", ErrInvalidFrame)
		}
	}
	if len(raw) == 0 || len(raw) > 10*1024*1024 {
		return result, fmt.Errorf("%w: frame size", ErrInvalidFrame)
	}
	var f frame
	dec := json.NewDecoder(bytes.NewReader(raw))
	dec.DisallowUnknownFields()
	if err := dec.Decode(&f); err != nil {
		return result, fmt.Errorf("%w: %v", ErrInvalidFrame, err)
	}
	if err := dec.Decode(new(any)); err != io.EOF {
		return result, fmt.Errorf("%w: trailing JSON", ErrInvalidFrame)
	}
	if f.Count == 0 || f.Count != len(f.Rows) {
		return result, fmt.Errorf("%w: row count mismatch/empty", ErrInvalidFrame)
	}
	present := map[string]bool{}
	for _, c := range f.Columns {
		if present[c] {
			return result, fmt.Errorf("%w: duplicate column %s", ErrInvalidFrame, c)
		}
		present[c] = true
	}
	dateField := "time"
	if !present[dateField] {
		dateField = "date"
	}
	for _, name := range []string{dateField, "open", "high", "low", "close", "volume"} {
		if !present[name] {
			return result, fmt.Errorf("%w: missing column %s", ErrInvalidFrame, name)
		}
	}
	result = BarsResult{Symbol: symbol, Count: f.Count, Rows: make([]dq.Bar, 0, f.Count)}
	for i, row := range f.Rows {
		for _, name := range []string{dateField, "open", "high", "low", "close", "volume"} {
			if _, ok := row[name]; !ok {
				return BarsResult{}, fmt.Errorf("%w: row %d missing %s", ErrInvalidFrame, i, name)
			}
		}
		date, err := parseDate(row[dateField])
		if err != nil {
			return BarsResult{}, fmt.Errorf("%w: row %d date: %v", ErrInvalidFrame, i, err)
		}
		names := []string{"open", "high", "low", "close", "volume"}
		vals := [5]float64{}
		for j, name := range names {
			v, err := number(row[name])
			if err != nil {
				return BarsResult{}, fmt.Errorf("%w: row %d %s: %v", ErrInvalidFrame, i, name, err)
			}
			vals[j] = v
		}
		result.Rows = append(result.Rows, dq.Bar{Symbol: symbol, Date: date, Open: vals[0], High: vals[1], Low: vals[2], Close: vals[3], Volume: vals[4]})
		if result.FirstDate == "" || date < result.FirstDate {
			result.FirstDate = date
		}
		if date > result.LastDate {
			result.LastDate = date
		}
	}
	if err := dq.Validate(result.Rows); err != nil {
		return BarsResult{}, fmt.Errorf("%w: %v", ErrInvalidFrame, err)
	}
	// Ensure vendor frames are ordered so resume markers and earliest/latest are unambiguous.
	for i := 1; i < len(result.Rows); i++ {
		if result.Rows[i].Date <= result.Rows[i-1].Date {
			return BarsResult{}, fmt.Errorf("%w: data not strictly chronological", ErrInvalidFrame)
		}
	}
	return result, nil
}

func parseDate(b json.RawMessage) (string, error) {
	var s string
	if err := json.Unmarshal(b, &s); err != nil {
		return "", errors.New("date must be a string")
	}
	var d time.Time
	var err error
	switch {
	case len(s) == 10:
		d, err = time.Parse("2006-01-02", s)
	case len(s) >= 19 && s[10] == 'T':
		for _, format := range []string{time.RFC3339Nano, "2006-01-02T15:04:05", "2006-01-02T15:04:05.000000"} {
			d, err = time.Parse(format, s)
			if err == nil {
				break
			}
		}
	default:
		return "", errors.New("unrecognized date timestamp")
	}
	if err != nil {
		return "", errors.New("expected ISO date or timestamp")
	}
	return d.Format("2006-01-02"), nil
}

func number(b json.RawMessage) (float64, error) {
	if bytes.Equal(b, []byte("null")) {
		return 0, errors.New("null numeric value")
	}
	var n json.Number
	if err := json.Unmarshal(b, &n); err == nil {
		v, e := n.Float64()
		if e == nil && !math.IsNaN(v) && !math.IsInf(v, 0) {
			return v, nil
		}
	}
	var s string
	if err := json.Unmarshal(b, &s); err == nil && s != "" {
		v, e := strconv.ParseFloat(s, 64)
		if e == nil && !math.IsNaN(v) && !math.IsInf(v, 0) {
			return v, nil
		}
	}
	return 0, errors.New("must be finite number")
}
