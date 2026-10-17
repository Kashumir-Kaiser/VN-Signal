package ingest

import (
    "bytes"
    "encoding/json"
    "fmt"
    "io"
    "math"
    "strings"

    "github.com/Kashumir-Kaiser/VN-Signal/go/internal/dq"
)

// BarIssue records source evidence, not a modified or replacement price.
// In particular, zero-volume records are not executed trades.
type BarIssue struct {
    Row int
    Date string
    Category string
    Reason string
}

// MarketFrame separates actual traded OHLC from zero-volume/eligibility-unverified
// observations and vendor contradictions. Every source record is accounted for.
// It does not invent prices, forward-fill, or adjust source values.
type MarketFrame struct {
    Bars BarsResult
    Issues []BarIssue
    SourceRows int
    ZeroVolume int
    InvalidTraded int
    FirstDate string
    LastDate string
}

func AnalyzeMarketBars(symbol string, raw []byte) (MarketFrame, error) {
    var result MarketFrame
    symbol = strings.ToUpper(strings.TrimSpace(symbol))
    if len(symbol) < 1 || len(symbol) > 12 {
        return result, fmt.Errorf("%w: invalid symbol", ErrInvalidFrame)
    }
    for _, r := range symbol {
        if !(r >= 'A' && r <= 'Z' || r >= '0' && r <= '9') {
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
    if f.Count < 1 || f.Count != len(f.Rows) {
        return result, fmt.Errorf("%w: missing/invalid source row count", ErrInvalidFrame)
    }
    columns := map[string]bool{}
    for _, name := range f.Columns {
        if columns[name] {
            return result, fmt.Errorf("%w: duplicate column %s", ErrInvalidFrame, name)
        }
        columns[name] = true
    }
    dateKey := "time"
    if !columns[dateKey] {
        dateKey = "date"
    }
    for _, field := range []string{dateKey, "open", "high", "low", "close", "volume"} {
        if !columns[field] {
            return result, fmt.Errorf("%w: missing column %s", ErrInvalidFrame, field)
        }
    }
    result.SourceRows = f.Count
    result.Bars = BarsResult{Symbol: symbol, Rows: make([]dq.Bar, 0, f.Count)}
    previous := ""
    for i, row := range f.Rows {
        for _, field := range []string{dateKey,"open","high","low","close","volume"} {
            if _, ok := row[field]; !ok {
                return MarketFrame{}, fmt.Errorf("%w: row %d missing field %s", ErrInvalidFrame, i, field)
            }
        }
        date, err := parseDate(row[dateKey])
        if err != nil || (previous != "" && date <= previous) {
            return MarketFrame{}, fmt.Errorf("%w: row %d has missing, duplicate or out-of-order session date", ErrInvalidFrame, i)
        }
        if previous == "" {
            result.FirstDate = date
        }
        result.LastDate = date
        previous = date
        issue := func(category, reason string) {
            if len(reason) > 120 {
                reason = reason[:120]
            }
            result.Issues = append(result.Issues, BarIssue{Row:i, Date:date, Category:category, Reason:reason})
        }
        volume, err := number(row["volume"])
        if err != nil || math.IsNaN(volume) || math.IsInf(volume,0) || volume < 0 {
            issue("INVALID_VOLUME","negative or nonnumeric volume")
            result.InvalidTraded++
            continue
        }
        if volume == 0 {
            issue("ZERO_VOLUME_UNVERIFIED","zero source volume; listing eligibility unverified")
            result.ZeroVolume++
            continue
        }
        prices := [4]float64{}
        invalidName := ""
        for j, name := range []string{"open","high","low","close"} {
            value, err := number(row[name])
            if err != nil || value <= 0 || math.IsNaN(value) || math.IsInf(value, 0) {
                invalidName = name
                break
            }
            prices[j] = value
        }
        if invalidName != "" {
            issue("INVALID_PRICE", fmt.Sprintf("invalid %s on traded session",invalidName))
            result.InvalidTraded++
            continue
        }
        bar := dq.Bar{Symbol:symbol, Date:date, Open:prices[0], High:prices[1], Low:prices[2], Close:prices[3], Volume:volume}
        if err := dq.Validate([]dq.Bar{bar}); err != nil {
            issue("INVALID_OHLC",err.Error())
            result.InvalidTraded++
            continue
        }
        result.Bars.Rows = append(result.Bars.Rows,bar)
    }
    result.Bars.Count = len(result.Bars.Rows)
    result.Bars.FirstDate = result.FirstDate
    result.Bars.LastDate = result.LastDate
    if result.Bars.Count + len(result.Issues) != result.SourceRows {
        return MarketFrame{}, fmt.Errorf("%w: unaccounted source rows",ErrInvalidFrame)
    }
    return result,nil
}
