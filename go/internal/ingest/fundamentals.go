package ingest

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"regexp"
	"sort"
	"strings"
	"time"

	"github.com/Kashumir-Kaiser/VN-Signal/go/internal/live"
)

// FundamentalJob is bounded to one statement family and one period frequency.
type FundamentalJob struct{ Symbol, StatementType, PeriodType, Mode string }
type FundamentalPeriod struct {
	Key, Type string
	End       time.Time
}
type FundamentalFrame struct {
	Count      int               `json:"count"`
	Columns    []string          `json:"columns"`
	Rows       []json.RawMessage `json:"rows"`
	Attributes map[string]any    `json:"attributes"`
}
type FundamentalLanding struct {
	JobID, Symbol, Source, StatementType, Mode string
	FetchedAt                                  time.Time
	SHA256                                     string
	Raw                                        json.RawMessage
	Frame                                      FundamentalFrame
	Periods                                    []FundamentalPeriod
}

type FundamentalLandingStore interface {
	CommitFundamentalLanding(context.Context, FundamentalLanding) error
}
type FundamentalQuarantineStore interface {
	QuarantineFundamentalFrame(context.Context, string, string, string, json.RawMessage) error
}

var quarterPeriod = regexp.MustCompile(`^([0-9]{4})-Q([1-4])$`)
var yearPeriod = regexp.MustCompile(`^[0-9]{4}$`)

func fundamentalPeriod(key, requested string) (FundamentalPeriod, error) {
	if m := quarterPeriod.FindStringSubmatch(key); m != nil && requested == "quarter" {
		y := atoi(m[1])
		if y == 0 {
			return FundamentalPeriod{}, errors.New("fundamental period year must be between 0001 and 9999")
		}
		q := atoi(m[2])
		return FundamentalPeriod{key, "quarter", time.Date(y, time.Month(q*3+1), 0, 0, 0, 0, 0, time.UTC)}, nil
	}
	if yearPeriod.MatchString(key) && requested == "year" {
		y := atoi(key)
		if y == 0 {
			return FundamentalPeriod{}, errors.New("fundamental period year must be between 0001 and 9999")
		}
		return FundamentalPeriod{key, "year", time.Date(y, 12, 31, 0, 0, 0, 0, time.UTC)}, nil
	}
	return FundamentalPeriod{}, fmt.Errorf("unsupported or mismatched period label %q (accepted quarter YYYY-Q1..YYYY-Q4, year YYYY)", key)
}

func atoi(s string) int {
	n := 0
	for _, r := range s {
		n = n*10 + int(r-'0')
	}
	return n
}

// AnalyzeFundamentalFrame validates provider attribution and every long-format row.
func AnalyzeFundamentalFrame(symbol, statement, periodType string, raw json.RawMessage) (FundamentalFrame, []FundamentalPeriod, error) {
	var f FundamentalFrame
	if len(raw) == 0 || len(raw) > 10<<20 || json.Unmarshal(raw, &f) != nil {
		return f, nil, errors.New("invalid or oversized fundamental frame")
	}
	if f.Count != len(f.Rows) || len(f.Rows) == 0 || len(f.Rows) > 10000 {
		return f, nil, errors.New("fundamental row count mismatch or out of bounds")
	}
	for _, c := range []string{"period", "id", "name", "order", "level", "unit", "value"} {
		found := false
		for _, got := range f.Columns {
			if got == c {
				found = true
			}
		}
		if !found {
			return f, nil, fmt.Errorf("missing fundamental column %s", c)
		}
	}
	frameSymbol, ok := f.Attributes["symbol"].(string)
	if !ok || strings.ToUpper(strings.TrimSpace(frameSymbol)) != strings.ToUpper(strings.TrimSpace(symbol)) {
		return f, nil, errors.New("fundamental frame symbol mismatch")
	}
	if f.Attributes["source"] != "vci" || f.Attributes["route"] != "fundamental.equity."+statement {
		return f, nil, errors.New("fundamental frame attribution mismatch")
	}
	keys := map[string]bool{}
	ids := map[string]map[string]bool{}
	periods := []FundamentalPeriod{}
	for _, r := range f.Rows {
		var row map[string]json.RawMessage
		if json.Unmarshal(r, &row) != nil {
			return f, nil, errors.New("fundamental row is not an object")
		}
		var key, id, name string
		var level, order json.Number
		if json.Unmarshal(row["period"], &key) != nil || json.Unmarshal(row["id"], &id) != nil || strings.TrimSpace(id) == "" || json.Unmarshal(row["name"], &name) != nil || strings.TrimSpace(name) == "" || json.Unmarshal(row["level"], &level) != nil || level.String() != "1" || json.Unmarshal(row["order"], &order) != nil {
			return f, nil, errors.New("invalid fundamental row identity, level, or order")
		}
		// Match the archive's JSON number and PostgreSQL integer contract before
		// dispatching a commit, so malformed frames reach quarantine instead.
		orderValue, orderErr := order.Int64()
		if !jsonNumberToken(row["level"]) || !jsonNumberToken(row["order"]) || orderErr != nil ||
			orderValue < -2147483648 || orderValue > 2147483647 {
			return f, nil, errors.New("fundamental order must be a JSON integer within PostgreSQL integer range")
		}
		if unit, present := row["unit"]; present && string(unit) != "null" {
			var unitName string
			if json.Unmarshal(unit, &unitName) != nil {
				return f, nil, errors.New("fundamental unit must be a string or null")
			}
		}
		p, e := fundamentalPeriod(key, periodType)
		if e != nil {
			return f, nil, e
		}
		if !keys[key] {
			keys[key] = true
			periods = append(periods, p)
			ids[key] = map[string]bool{}
		}
		if ids[key][id] {
			return f, nil, errors.New("duplicate fundamental line id within period")
		}
		ids[key][id] = true
		if string(row["value"]) != "null" {
			var num json.Number
			if !jsonNumberToken(row["value"]) || json.Unmarshal(row["value"], &num) != nil {
				return f, nil, errors.New("fundamental value must be numeric or null")
			}
		}
	}
	sort.Slice(periods, func(i, j int) bool { return periods[i].End.Before(periods[j].End) })
	return f, periods, nil
}

func jsonNumberToken(raw json.RawMessage) bool {
	value := strings.TrimSpace(string(raw))
	return len(value) > 0 && (value[0] == '-' || value[0] >= '0' && value[0] <= '9')
}

func validateFundamentalJob(j FundamentalJob) error {
	if !regexp.MustCompile(`^[A-Z0-9]{1,12}$`).MatchString(j.Symbol) {
		return errors.New("invalid symbol")
	}
	if j.StatementType != "income_statement" && j.StatementType != "balance_sheet" && j.StatementType != "cash_flow" {
		return errors.New("unsupported statement type")
	}
	if j.PeriodType != "quarter" && j.PeriodType != "year" {
		return errors.New("unsupported period type")
	}
	if j.Mode != "backfill" && j.Mode != "observed" {
		return errors.New("unsupported availability mode")
	}
	return nil
}

// RunFundamentalsBackfill only accepts the VCI capability validated by caller; each
// attempt uses the recorded audit boundary and a fresh pre-call quota check.
func (r *Runner) RunFundamentalsBackfill(ctx context.Context, jobs []FundamentalJob) (RunSummary, error) {
	var sum RunSummary
	if r == nil || r.Gateway == nil || r.Store == nil || r.Now == nil {
		return sum, errors.New("runner not configured")
	}
	if len(jobs) == 0 || len(jobs) > 100 {
		return sum, errors.New("fundamental job count must be 1..100")
	}
	commit, ok := r.Store.(FundamentalLandingStore)
	if !ok {
		return sum, errors.New("fundamental archival store unavailable")
	}
	quarantine, ok := r.Store.(FundamentalQuarantineStore)
	if !ok {
		return sum, errors.New("fundamental quarantine store unavailable")
	}
	// Freeze a run's local observation day; actual availability remains FetchedAt.
	observationDay := r.Now().In(time.FixedZone("Asia/Ho_Chi_Minh", 7*3600)).Format("2006-01-02")
	for _, j := range jobs {
		if e := validateFundamentalJob(j); e != nil {
			return sum, e
		}
		key := fmt.Sprintf("fundamental:%s:%s:%s:%s", j.StatementType, j.PeriodType, j.Mode, j.Symbol)
		if j.Mode == "observed" {
			key += ":" + observationDay
		}
		done, e := r.Store.Completed(ctx, key)
		if e != nil {
			return sum, e
		}
		if done {
			sum.Skipped++
			continue
		}
		if r.BeforeCall != nil {
			if e = r.BeforeCall(ctx); e != nil {
				return sum, fmt.Errorf("pre-call quota verification: %w", e)
			}
		}
		bj := BackfillJob{Route: j.StatementType, Symbol: j.Symbol}
		reply, e := r.Gateway.CallRecorded(ctx, map[string]any{"id": key, "op": j.StatementType, "symbol": j.Symbol, "source": "vci", "period": j.PeriodType}, live.CallAudit{
			Reserve: func(c context.Context, at time.Time) (time.Time, error) {
				return r.Store.ReserveAttempt(c, bj, key, "vci", at)
			}, Dispatch: func(c context.Context) error { return r.Store.MarkDispatch(c, key) }, Finish: func(c context.Context, o, reason string) error { return r.Store.MarkOutcome(c, key, o, reason) },
		})
		if e != nil {
			return sum, e
		}
		if reply.ID != key || !reply.OK {
			return sum, errors.New("fundamental route failed or response id mismatch")
		}
		frame, periods, e := AnalyzeFundamentalFrame(j.Symbol, j.StatementType, j.PeriodType, reply.Data)
		if e != nil {
			if q := quarantine.QuarantineFundamentalFrame(ctx, key, "vci", e.Error(), reply.Data); q != nil {
				return sum, errors.Join(e, q)
			}
			sum.Blocked++
			continue
		}
		sha := sha256.Sum256(reply.Data)
		e = commit.CommitFundamentalLanding(ctx, FundamentalLanding{JobID: key, Symbol: j.Symbol, Source: "vci", StatementType: j.StatementType, Mode: j.Mode, FetchedAt: r.Now().UTC(), SHA256: hex.EncodeToString(sha[:]), Raw: append(json.RawMessage(nil), reply.Data...), Frame: frame, Periods: periods})
		if e != nil {
			return sum, e
		}
		sum.Committed++
	}
	return sum, nil
}
