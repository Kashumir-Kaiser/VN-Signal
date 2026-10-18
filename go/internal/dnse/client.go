// Package dnse reads historical stock OHLCV from DNSE Entrade's public chart API.
package dnse

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

const defaultBaseURL = "https://services.entrade.com.vn/chart-api/v2/ohlcs/stock"
const maxResponseBytes = 10 * 1024 * 1024

var symbolPattern = regexp.MustCompile(`^[A-Z0-9]{1,12}$`)

type Bar struct {
	SourceRow int
	Date      string
	Open      *float64
	High      *float64
	Low       *float64
	Close     *float64
	Volume    *float64
}

type History struct {
	Rows                []Bar
	FieldLengthMismatch bool
	Raw                 []byte
	RequestURL          string
	HTTPStatus          int
}

type Client struct {
	HTTP    *http.Client
	BaseURL string
}

func NewClient() *Client {
	return &Client{HTTP: &http.Client{Timeout: 20 * time.Second}, BaseURL: defaultBaseURL}
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
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, out.RequestURL, nil)
	if err != nil {
		return out, errors.New("create DNSE request")
	}
	req.Header.Set("Accept", "application/json")
	req.Header.Set("User-Agent", "VN-Signal/1.0 historical-data")
	resp, err := httpClient.Do(req)
	if err != nil {
		return out, fmt.Errorf("DNSE transport error: %w", err)
	}
	defer resp.Body.Close()
	out.HTTPStatus = resp.StatusCode
	body, err := io.ReadAll(io.LimitReader(resp.Body, maxResponseBytes+1))
	if err != nil {
		return out, errors.New("read DNSE response")
	}
	if len(body) > maxResponseBytes {
		return out, errors.New("DNSE response exceeds 10 MiB limit")
	}
	out.Raw = body
	if resp.StatusCode == http.StatusTooManyRequests {
		return out, errors.New("DNSE rate limited request")
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return out, fmt.Errorf("DNSE HTTP status %d", resp.StatusCode)
	}
	rows, mismatch, err := ParseHistory(body, start, end)
	if err != nil {
		return out, err
	}
	out.Rows = rows
	out.FieldLengthMismatch = mismatch
	return out, nil
}

func (c *Client) RequestURL(symbol, start, end string) (string, error) {
	symbol = strings.ToUpper(strings.TrimSpace(symbol))
	if !symbolPattern.MatchString(symbol) || !validDate(start) || !validDate(end) || start > end {
		return "", errors.New("invalid DNSE history request")
	}
	base := defaultBaseURL
	if c != nil && strings.TrimSpace(c.BaseURL) != "" {
		base = strings.TrimRight(c.BaseURL, "/")
	}
	parsed, err := url.Parse(base)
	if err != nil || parsed.Scheme != "https" || parsed.Host == "" {
		return "", errors.New("invalid DNSE endpoint")
	}
	from := dateUTC(start).Unix()
	to := dateUTC(end).Add(24 * time.Hour).Unix()
	query := parsed.Query()
	query.Set("symbol", symbol)
	query.Set("resolution", "1D")
	query.Set("from", strconv.FormatInt(from, 10))
	query.Set("to", strconv.FormatInt(to, 10))
	parsed.RawQuery = query.Encode()
	return parsed.String(), nil
}

type wireSeries struct {
	T        []json.RawMessage `json:"t"`
	O        []json.RawMessage `json:"o"`
	H        []json.RawMessage `json:"h"`
	L        []json.RawMessage `json:"l"`
	C        []json.RawMessage `json:"c"`
	V        []json.RawMessage `json:"v"`
	NextTime json.RawMessage   `json:"nextTime"`
}

func ParseHistory(raw []byte, start, end string) ([]Bar, bool, error) {
	if len(raw) == 0 || len(raw) > maxResponseBytes || !validDate(start) || !validDate(end) || start > end {
		return nil, false, errors.New("invalid DNSE frame bounds")
	}
	var frame wireSeries
	if err := json.Unmarshal(raw, &frame); err != nil {
		return nil, false, errors.New("invalid DNSE JSON frame")
	}
	if len(frame.T) == 0 {
		// All market fields must also be empty for a well-formed empty response.
		if len(frame.O)+len(frame.H)+len(frame.L)+len(frame.C)+len(frame.V) != 0 {
			return nil, true, nil
		}
		return []Bar{}, false, nil
	}
	mismatch := len(frame.O) != len(frame.T) || len(frame.H) != len(frame.T) ||
		len(frame.L) != len(frame.T) || len(frame.C) != len(frame.T) || len(frame.V) != len(frame.T)
	rows := make([]Bar, 0, len(frame.T))
	previousDate := ""
	previousTimestamp := int64(0)
	for i, rawTime := range frame.T {
		var seconds int64
		if err := json.Unmarshal(rawTime, &seconds); err != nil || seconds <= 0 {
			return nil, mismatch, fmt.Errorf("DNSE row %d has invalid timestamp", i)
		}
		date := time.Unix(seconds, 0).In(vietnamLocation).Format("2006-01-02")
		if date < start || date > end || seconds <= previousTimestamp || (previousDate != "" && date < previousDate) {
			return nil, mismatch, fmt.Errorf("DNSE row %d is outside range or not ordered by timestamp", i)
		}
		previousDate = date
		previousTimestamp = seconds
		bar := Bar{SourceRow: i, Date: date}
		var err error
		bar.Open, err = field(frame.O, i)
		if err != nil {
			return nil, mismatch, fmt.Errorf("DNSE row %d open is malformed", i)
		}
		bar.High, err = field(frame.H, i)
		if err != nil {
			return nil, mismatch, fmt.Errorf("DNSE row %d high is malformed", i)
		}
		bar.Low, err = field(frame.L, i)
		if err != nil {
			return nil, mismatch, fmt.Errorf("DNSE row %d low is malformed", i)
		}
		bar.Close, err = field(frame.C, i)
		if err != nil {
			return nil, mismatch, fmt.Errorf("DNSE row %d close is malformed", i)
		}
		bar.Volume, err = field(frame.V, i)
		if err != nil {
			return nil, mismatch, fmt.Errorf("DNSE row %d volume is malformed", i)
		}
		rows = append(rows, bar)
	}
	return rows, mismatch, nil
}

var vietnamLocation = time.FixedZone("Asia/Ho_Chi_Minh", 7*60*60)

func field(values []json.RawMessage, index int) (*float64, error) {
	if index >= len(values) {
		return nil, nil
	}
	raw := values[index]
	if string(raw) == "null" {
		return nil, nil
	}
	var value float64
	if err := json.Unmarshal(raw, &value); err != nil || math.IsNaN(value) || math.IsInf(value, 0) {
		return nil, errors.New("nonnumeric field")
	}
	return &value, nil
}

func validDate(value string) bool {
	t, err := time.Parse("2006-01-02", value)
	return err == nil && t.Format("2006-01-02") == value
}

func dateUTC(value string) time.Time {
	t, _ := time.Parse("2006-01-02", value)
	return t.UTC()
}
