package ingest

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math"
	"time"

	"github.com/Kashumir-Kaiser/VN-Signal/go/internal/dq"
)

// IndexFrame preserves only validated rows; the original response is archived
// byte-for-byte alongside it. VNINDEX is the only index currently accepted.
type IndexFrame struct {
	Rows                []dq.Bar
	FirstDate, LastDate string
}
type IndexLanding struct {
	JobID, Symbol, Source string
	FetchedAt             time.Time
	SHA256                string
	Raw                   json.RawMessage
	Frame                 IndexFrame
}

func AnalyzeIndexBarsForSource(symbol, source string, raw []byte) (IndexFrame, error) {
	var out IndexFrame
	if symbol != "VNINDEX" || (source != "kbs" && source != "vci") || len(raw) == 0 || len(raw) > 10*1024*1024 {
		return out, errors.New("unsupported index capability")
	}
	var f frame
	d := json.NewDecoder(bytes.NewReader(raw))
	d.DisallowUnknownFields()
	if err := d.Decode(&f); err != nil {
		return out, err
	}
	if err := d.Decode(new(any)); err != io.EOF {
		return out, errors.New("trailing index JSON")
	}
	var a frameAttribution
	if err := json.Unmarshal(f.Attributes, &a); err != nil {
		return out, err
	}
	if a.Source != source || a.Route != "market.index.ohlcv" || f.Count < 1 || f.Count != len(f.Rows) {
		return out, errors.New("missing or mismatched index provider attribution")
	}
	cols := map[string]bool{}
	for _, c := range f.Columns {
		if cols[c] {
			return out, errors.New("duplicate index column")
		}
		cols[c] = true
	}
	dateKey := "time"
	if !cols[dateKey] {
		dateKey = "date"
	}
	for _, c := range []string{dateKey, "open", "high", "low", "close", "volume"} {
		if !cols[c] {
			return out, fmt.Errorf("missing index column %s", c)
		}
	}
	prev := ""
	out.Rows = make([]dq.Bar, 0, f.Count)
	for _, row := range f.Rows {
		date, err := parseDate(row[dateKey])
		if err != nil || date <= prev {
			return IndexFrame{}, errors.New("invalid index session order")
		}
		if out.FirstDate == "" {
			out.FirstDate = date
		}
		out.LastDate = date
		prev = date
		vals := [4]float64{}
		for i, k := range []string{"open", "high", "low", "close"} {
			vals[i], err = number(row[k])
			if err != nil || math.IsNaN(vals[i]) || math.IsInf(vals[i], 0) || vals[i] <= 0 {
				return IndexFrame{}, errors.New("invalid index OHLC")
			}
		}
		vol, err := number(row["volume"])
		if err != nil || math.IsNaN(vol) || math.IsInf(vol, 0) || vol < 0 {
			return IndexFrame{}, errors.New("invalid index volume")
		}
		b := dq.Bar{Symbol: symbol, Date: date, Open: vals[0], High: vals[1], Low: vals[2], Close: vals[3], Volume: vol}
		if err := dq.Validate([]dq.Bar{b}); err != nil {
			return IndexFrame{}, err
		}
		out.Rows = append(out.Rows, b)
	}
	return out, nil
}
