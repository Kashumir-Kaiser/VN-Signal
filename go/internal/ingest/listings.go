package ingest

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"reflect"
	"sort"
	"strings"
	"time"
)

var ErrInvalidListing = errors.New("incomplete or invalid equity listing snapshot")

// Listing is one equity observed in the official vnstock v5 list_by_exchange frame.
// Industry is an ICB level-two code, NOT a human-readable industry classification.
type Listing struct {
	Symbol   string
	Exchange string
	Industry string
}

type ListingSnapshot struct {
	AsOf             string
	CollectedAt      time.Time
	Source           string
	MinSymbols       int
	ProviderRows     int
	ExcludedDelisted int
	Frame            json.RawMessage
	SHA256           string
	Listings         []Listing
}

type listingFrame struct {
	Columns    []string                     `json:"columns"`
	Count      int                          `json:"count"`
	Rows       []map[string]json.RawMessage `json:"rows"`
	Attributes json.RawMessage              `json:"attributes"`
}

func decodeListingFrame(raw []byte, minSymbols int) ([]Listing, error) {
	if minSymbols < 3 || len(raw) == 0 || len(raw) > 10*1024*1024 {
		return nil, fmt.Errorf("%w: size/minimum", ErrInvalidListing)
	}
	var frame listingFrame
	d := json.NewDecoder(bytes.NewReader(raw))
	d.DisallowUnknownFields()
	if err := d.Decode(&frame); err != nil {
		return nil, fmt.Errorf("%w: %v", ErrInvalidListing, err)
	}
	if err := d.Decode(new(any)); err != io.EOF {
		return nil, fmt.Errorf("%w: extra data", ErrInvalidListing)
	}
	if frame.Count != len(frame.Rows) {
		return nil, fmt.Errorf("%w: incomplete provider row count", ErrInvalidListing)
	}
	columns := make(map[string]bool, len(frame.Columns))
	for _, col := range frame.Columns {
		if col == "" || columns[col] {
			return nil, fmt.Errorf("%w: duplicate/empty column", ErrInvalidListing)
		}
		columns[col] = true
	}
	if !columns["symbol"] || !columns["exchange"] {
		return nil, fmt.Errorf("%w: missing symbol/exchange", ErrInvalidListing)
	}
	var listings []Listing
	seen := make(map[string]bool, len(frame.Rows))
	exchanges := make(map[string]bool)
	for i, row := range frame.Rows {
		for key := range row {
			if !columns[key] {
				return nil, fmt.Errorf("%w: unknown row column %q", ErrInvalidListing, key)
			}
		}
		var symbol, exchange string
		if json.Unmarshal(row["symbol"], &symbol) != nil || json.Unmarshal(row["exchange"], &exchange) != nil {
			return nil, fmt.Errorf("%w: invalid symbol/exchange at %d", ErrInvalidListing, i)
		}
		symbol = strings.ToUpper(strings.TrimSpace(symbol))
		if len(symbol) < 1 || len(symbol) > 12 || seen[symbol] {
			return nil, fmt.Errorf("%w: bad or repeated symbol %q", ErrInvalidListing, symbol)
		}
		for _, ch := range symbol {
			if !(ch >= 'A' && ch <= 'Z' || ch >= '0' && ch <= '9') {
				return nil, fmt.Errorf("%w: invalid symbol %q", ErrInvalidListing, symbol)
			}
		}
		exchange = strings.ToUpper(strings.TrimSpace(exchange))
		if exchange != "HOSE" && exchange != "HNX" && exchange != "UPCOM" && exchange != "DELISTED" {
			return nil, fmt.Errorf("%w: unknown exchange %q", ErrInvalidListing, exchange)
		}
		industry := ""
		if val, ok := row["icb_code_lv2"]; ok && string(val) != "null" {
			if err := json.Unmarshal(val, &industry); err != nil {
				var n json.Number
				if err := json.Unmarshal(val, &n); err != nil {
					return nil, fmt.Errorf("%w: bad industry code", ErrInvalidListing)
				}
				industry = n.String()
			}
			if len(industry) > 12 {
				return nil, fmt.Errorf("%w: industry code length", ErrInvalidListing)
			}
			for _, ch := range industry {
				if ch < '0' || ch > '9' {
					return nil, fmt.Errorf("%w: industry code not numeric", ErrInvalidListing)
				}
			}
		}
		seen[symbol] = true
		// The live provider includes a DELISTED category without the original
		// exchange. Preserve it in Frame/raw landing, but never make it active
		// or eligible for a market-data backfill.
		if exchange == "DELISTED" {
			continue
		}
		exchanges[exchange] = true
		listings = append(listings, Listing{Symbol: symbol, Exchange: exchange, Industry: industry})
	}
	if len(listings) < minSymbols {
		return nil, fmt.Errorf("%w: fewer than %d current listed symbols", ErrInvalidListing, minSymbols)
	}
	if len(exchanges) != 3 {
		return nil, fmt.Errorf("%w: all three exchanges required", ErrInvalidListing)
	}
	sort.Slice(listings, func(i, j int) bool { return listings[i].Symbol < listings[j].Symbol })
	return listings, nil
}

// ParseListingProbe accepts ONLY an active Go probe with the captured, complete
// equity_list response. Passive probes and earlier summary-only files fail closed.
func ParseListingProbe(raw []byte, minSymbols int) (ListingSnapshot, error) {
	var out ListingSnapshot
	if len(raw) == 0 || len(raw) > 12*1024*1024 {
		return out, ErrInvalidListing
	}
	var report struct {
		At     string `json:"at"`
		Active bool   `json:"active"`
		Routes map[string]struct {
			Available bool `json:"available"`
			Count     int  `json:"count"`
		} `json:"routes"`
		ListingFrame json.RawMessage `json:"listing_frame"`
	}
	if err := json.Unmarshal(raw, &report); err != nil || !report.Active {
		return out, fmt.Errorf("%w: active probe required", ErrInvalidListing)
	}
	observed, err := time.Parse(time.RFC3339Nano, report.At)
	if err != nil || observed.IsZero() {
		return out, fmt.Errorf("%w: invalid timestamp", ErrInvalidListing)
	}
	route, ok := report.Routes["equity_list"]
	if !ok || !route.Available {
		return out, fmt.Errorf("%w: listing route unavailable", ErrInvalidListing)
	}
	listings, err := decodeListingFrame(report.ListingFrame, minSymbols)
	if err != nil {
		return out, err
	}
	var frameMeta struct {
		Count int `json:"count"`
	}
	if err := json.Unmarshal(report.ListingFrame, &frameMeta); err != nil || frameMeta.Count != route.Count {
		return out, fmt.Errorf("%w: probe count disagrees with provider frame", ErrInvalidListing)
	}
	vntz := time.FixedZone("Asia/Ho_Chi_Minh", 7*3600)
	sum := sha256.Sum256(report.ListingFrame)
	return ListingSnapshot{
		AsOf: observed.In(vntz).Format("2006-01-02"), CollectedAt: observed.UTC(), Source: "vci",
		MinSymbols: minSymbols, ProviderRows: frameMeta.Count,
		ExcludedDelisted: frameMeta.Count - len(listings),
		Frame: append(json.RawMessage(nil), report.ListingFrame...),
		SHA256: hex.EncodeToString(sum[:]), Listings: listings,
	}, nil
}

// RevalidateBeforeImport prevents callers constructing a fabricated or mutated
// canonical listing set that disagrees with the original vendor frame.
func RevalidateBeforeImport(s ListingSnapshot) error {
	rows, err := decodeListingFrame(s.Frame, s.MinSymbols)
	if err != nil {
		return err
	}
	var frameMeta struct {
		Count int `json:"count"`
	}
	if err := json.Unmarshal(s.Frame, &frameMeta); err != nil {
		return fmt.Errorf("%w: unreadable provider count", ErrInvalidListing)
	}
	d := sha256.Sum256(s.Frame)
	if s.Source != "vci" || s.AsOf == "" || s.CollectedAt.IsZero() ||
		s.CollectedAt.In(time.FixedZone("Asia/Ho_Chi_Minh", 7*3600)).Format("2006-01-02") != s.AsOf ||
		s.ProviderRows != frameMeta.Count || s.ExcludedDelisted != frameMeta.Count-len(rows) ||
		s.SHA256 != hex.EncodeToString(d[:]) || !reflect.DeepEqual(rows, s.Listings) {
		return fmt.Errorf("%w: canonical listing differs from raw frame", ErrInvalidListing)
	}
	return nil
}
