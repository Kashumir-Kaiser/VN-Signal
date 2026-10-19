// Package vndirect reads source-attributed raw and retrospectively adjusted
// historical OHLCV from VNDIRECT's public Finfo API.
package vndirect

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math"
	"net/http"
	"net/url"
	"regexp"
	"strconv"
	"strings"
	"time"
)

const defaultBaseURL = "https://api-finfo.vndirect.com.vn/v4/stock_prices"
const maxResponseBytes = 10 * 1024 * 1024
const pageSize = 5000

var symbolPattern = regexp.MustCompile(`^[A-Z0-9]{1,12}$`)

type Bar struct {
	SourceRow      int
	Date           string
	ProviderCode   string
	TickerMismatch bool
	DuplicateDate  bool
	Open           *float64
	High           *float64
	Low            *float64
	Close          *float64
	ReferencePrice *float64
	AveragePrice   *float64
	ExchangeCode   string
	AdjustedOpen   *float64
	AdjustedHigh   *float64
	AdjustedLow    *float64
	AdjustedClose  *float64
	Volume         *float64 // nmVolume: normal-market volume, matching VCI's reported volume basis.
	PTVolume       *float64 // Archived for diagnostics; excluded from normal-market volume.
}

type History struct {
	Rows       []Bar
	Raw        []byte
	RequestURL string
	HTTPStatus int
}

type Client struct {
	HTTP    *http.Client
	BaseURL string
}

func NewClient() *Client {
	return &Client{HTTP: &http.Client{Timeout: 25 * time.Second}, BaseURL: defaultBaseURL}
}

func (c *Client) RequestURL(symbol, start, end string) (string, error) {
	symbol = strings.ToUpper(strings.TrimSpace(symbol))
	if !symbolPattern.MatchString(symbol) || !validDate(start) || !validDate(end) || start > end {
		return "", errors.New("invalid VNDIRECT history request")
	}
	base := defaultBaseURL
	if c != nil && strings.TrimSpace(c.BaseURL) != "" {
		base = strings.TrimRight(c.BaseURL, "/")
	}
	parsed, err := url.Parse(base)
	if err != nil || parsed.Scheme != "https" || parsed.Host == "" {
		return "", errors.New("invalid VNDIRECT endpoint")
	}
	query := parsed.Query()
	query.Set("q", fmt.Sprintf("code:%s~date:gte:%s~date:lte:%s", symbol, start, end))
	query.Set("sort", "date:asc")
	query.Set("size", strconv.Itoa(pageSize))
	query.Set("page", "1")
	parsed.RawQuery = query.Encode()
	return parsed.String(), nil
}

func (c *Client) FetchHistory(ctx context.Context, symbol, start, end string) (History, error) {
	var out History
	requestURL, err := c.RequestURL(symbol, start, end)
	if err != nil {
		return out, err
	}
	out.RequestURL = requestURL
	httpClient := http.DefaultClient
	if c != nil && c.HTTP != nil {
		httpClient = c.HTTP
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, requestURL, nil)
	if err != nil {
		return out, errors.New("create VNDIRECT request")
	}
	req.Header.Set("Accept", "application/json")
	req.Header.Set("User-Agent", "VN-Signal/1.0 historical-data")
	resp, err := httpClient.Do(req)
	if err != nil {
		return out, fmt.Errorf("VNDIRECT transport error: %w", err)
	}
	defer resp.Body.Close()
	out.HTTPStatus = resp.StatusCode
	body, err := io.ReadAll(io.LimitReader(resp.Body, maxResponseBytes+1))
	if err != nil {
		return out, errors.New("read VNDIRECT response")
	}
	if len(body) > maxResponseBytes {
		return out, errors.New("VNDIRECT response exceeds 10 MiB limit")
	}
	out.Raw = body
	if resp.StatusCode == http.StatusTooManyRequests {
		return out, errors.New("VNDIRECT rate limited request")
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return out, fmt.Errorf("VNDIRECT HTTP status %d", resp.StatusCode)
	}
	rows, err := ParseHistory(body, strings.ToUpper(strings.TrimSpace(symbol)), start, end)
	if err != nil {
		return out, err
	}
	out.Rows = rows
	return out, nil
}

type wireResponse struct {
	Data          []wireBar `json:"data"`
	CurrentPage   int       `json:"currentPage"`
	Size          int       `json:"size"`
	TotalElements int       `json:"totalElements"`
	TotalPages    int       `json:"totalPages"`
}

type wireBar struct {
	Code          string   `json:"code"`
	Date          string   `json:"date"`
	Open          *float64 `json:"open"`
	High          *float64 `json:"high"`
	Low           *float64 `json:"low"`
	Close         *float64 `json:"close"`
	BasicPrice    *float64 `json:"basicPrice"`
	Average       *float64 `json:"average"`
	Floor         string   `json:"floor"`
	AdjustedOpen  *float64 `json:"adOpen"`
	AdjustedHigh  *float64 `json:"adHigh"`
	AdjustedLow   *float64 `json:"adLow"`
	AdjustedClose *float64 `json:"adClose"`
	NMVolume      *float64 `json:"nmVolume"`
	PTVolume      *float64 `json:"ptVolume"`
}

func ParseHistory(raw []byte, symbol, start, end string) ([]Bar, error) {
	symbol = strings.ToUpper(strings.TrimSpace(symbol))
	if len(raw) == 0 || len(raw) > maxResponseBytes || !symbolPattern.MatchString(symbol) ||
		!validDate(start) || !validDate(end) || start > end {
		return nil, errors.New("invalid VNDIRECT frame bounds")
	}
	var frame wireResponse
	if err := json.Unmarshal(raw, &frame); err != nil {
		return nil, errors.New("invalid VNDIRECT JSON frame")
	}
	if frame.TotalElements > len(frame.Data) || frame.TotalPages > 1 {
		return nil, errors.New("VNDIRECT response is unexpectedly truncated")
	}
	rows := make([]Bar, 0, len(frame.Data))
	previous := ""
	for i, item := range frame.Data {
		date := strings.TrimSpace(item.Date)
		if len(date) > 10 {
			date = date[:10]
		}
		if !validDate(date) || date < start || date > end || (previous != "" && date < previous) {
			return nil, fmt.Errorf("VNDIRECT row %d is outside range or not uniquely ordered", i)
		}
		previous = date
		for _, value := range []*float64{item.Open, item.High, item.Low, item.Close,
			item.BasicPrice, item.Average, item.AdjustedOpen, item.AdjustedHigh, item.AdjustedLow, item.AdjustedClose} {
			if value != nil && (math.IsNaN(*value) || math.IsInf(*value, 0)) {
				return nil, fmt.Errorf("VNDIRECT row %d has a nonfinite price", i)
			}
		}
		if item.NMVolume != nil && (math.IsNaN(*item.NMVolume) || math.IsInf(*item.NMVolume, 0)) {
			return nil, fmt.Errorf("VNDIRECT row %d has a nonfinite volume", i)
		}
		if item.PTVolume != nil && (math.IsNaN(*item.PTVolume) || math.IsInf(*item.PTVolume, 0)) {
			return nil, fmt.Errorf("VNDIRECT row %d has a nonfinite put-through volume", i)
		}
		providerCode := strings.ToUpper(strings.TrimSpace(item.Code))
		rows = append(rows, Bar{SourceRow: i, Date: date, ProviderCode: providerCode,
			TickerMismatch: !strings.EqualFold(providerCode, symbol), Open: item.Open, High: item.High,
			Low: item.Low, Close: item.Close, ReferencePrice: item.BasicPrice, AveragePrice: item.Average,
			ExchangeCode: strings.ToUpper(strings.TrimSpace(item.Floor)),
			AdjustedOpen: item.AdjustedOpen, AdjustedHigh: item.AdjustedHigh, AdjustedLow: item.AdjustedLow,
			AdjustedClose: item.AdjustedClose, Volume: item.NMVolume, PTVolume: item.PTVolume})
	}
	counts := make(map[string]int, len(rows))
	for _, row := range rows {
		if !row.TickerMismatch {
			counts[row.Date+"\x00"+row.ProviderCode]++
		}
	}
	for i := range rows {
		if !rows[i].TickerMismatch && counts[rows[i].Date+"\x00"+rows[i].ProviderCode] > 1 {
			rows[i].DuplicateDate = true
		}
	}
	return rows, nil
}

func validDate(value string) bool {
	t, err := time.Parse("2006-01-02", value)
	return err == nil && t.Format("2006-01-02") == value
}
