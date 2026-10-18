package dq

import (
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"math"
	"sort"
	"strings"
	"time"
)

type listedRow struct{ symbol, exchange, industry string }

func parseVerifiedListingFrame(raw []byte) ([]listedRow, error) {
	var frame struct {
		Columns []string                     `json:"columns"`
		Count   int                          `json:"count"`
		Rows    []map[string]json.RawMessage `json:"rows"`
	}
	if len(raw) < 2 || len(raw) > 10*1024*1024 || json.Unmarshal(raw, &frame) != nil || frame.Count != len(frame.Rows) {
		return nil, errors.New("invalid archived listing frame/count")
	}
	columns := map[string]bool{}
	for _, col := range frame.Columns {
		if col == "" || columns[col] {
			return nil, errors.New("invalid archived listing columns")
		}
		columns[col] = true
	}
	if !columns["symbol"] || !columns["exchange"] {
		return nil, errors.New("archived listing frame lacks symbol/exchange")
	}
	seen, exchanges := map[string]bool{}, map[string]bool{}
	listed := make([]listedRow, 0, frame.Count)
	for i, row := range frame.Rows {
		for key := range row {
			if !columns[key] {
				return nil, fmt.Errorf("unexpected listing field %q at row %d", key, i)
			}
		}
		var symbol, exchange string
		if json.Unmarshal(row["symbol"], &symbol) != nil || json.Unmarshal(row["exchange"], &exchange) != nil {
			return nil, fmt.Errorf("invalid listing symbol/exchange at row %d", i)
		}
		symbol = strings.ToUpper(strings.TrimSpace(symbol))
		exchange = strings.ToUpper(strings.TrimSpace(exchange))
		if symbol == "" || len(symbol) > 12 || seen[symbol] {
			return nil, fmt.Errorf("empty, oversized or repeated listing symbol %q", symbol)
		}
		for _, r := range symbol {
			if !(r >= 'A' && r <= 'Z' || r >= '0' && r <= '9') {
				return nil, fmt.Errorf("invalid listing symbol %q", symbol)
			}
		}
		if exchange != "HOSE" && exchange != "HNX" && exchange != "UPCOM" && exchange != "DELISTED" {
			return nil, fmt.Errorf("invalid listing exchange %q", exchange)
		}
		industry := ""
		if rawIndustry, ok := row["icb_code_lv2"]; ok && string(rawIndustry) != "null" {
			if json.Unmarshal(rawIndustry, &industry) != nil {
				var n json.Number
				if json.Unmarshal(rawIndustry, &n) != nil {
					return nil, fmt.Errorf("invalid industry code at row %d", i)
				}
				industry = n.String()
			}
			for _, r := range industry {
				if r < '0' || r > '9' {
					return nil, fmt.Errorf("invalid industry code at row %d", i)
				}
			}
		}
		seen[symbol] = true
		if exchange == "DELISTED" {
			continue
		}
		exchanges[exchange] = true
		listed = append(listed, listedRow{symbol: symbol, exchange: exchange, industry: industry})
	}
	if len(listed) < 1000 || len(exchanges) != 3 {
		return nil, errors.New("archived listing frame is not a complete three-exchange universe")
	}
	sort.Slice(listed, func(i, j int) bool { return listed[i].symbol < listed[j].symbol })
	return listed, nil
}

func verifiedListingSnapshot(raw []byte, digest string, relational []listedRow) ([]listedRow, error) {
	if len(raw) < 2 || len(raw) > 10*1024*1024 {
		return nil, errors.New("missing or oversized archived listing frame")
	}
	sum := sha256.Sum256(raw)
	if !strings.EqualFold(hex.EncodeToString(sum[:]), digest) {
		return nil, errors.New("listing landing checksum mismatch")
	}
	listed, err := parseVerifiedListingFrame(raw)
	if err != nil {
		return nil, err
	}
	if len(listed) != len(relational) {
		return nil, errors.New("listing frame/snapshot count differs")
	}
	for i := range listed {
		if listed[i] != relational[i] {
			return nil, fmt.Errorf("relational listing differs from archived frame at row %d", i)
		}
	}
	return listed, nil
}

func tenureEligibleSymbols(listed []listedRow, tenure map[string]int) []string {
	eligible := make([]string, 0, len(listed))
	for _, item := range listed {
		if tenure[item.symbol] >= TierAMinSessions {
			eligible = append(eligible, item.symbol)
		}
	}
	return eligible
}

// loadVerifiedTradeTenure uses positive-volume canonical bars as a conservative
// lower bound on listed sessions: each such source-backed trade proves the
// security existed on that recorded exchange session. The candidate universe
// is still the exact verified as-of listing snapshot, and no date at or after
// asOf is counted. Raw landing hashes must match before a bar earns credit.
func loadVerifiedTradeTenure(ctx context.Context, tx *sql.Tx, asOf string) (map[string]int, error) {
	rows, err := tx.QueryContext(ctx, `WITH verified_landings AS MATERIALIZED (
		SELECT ingest_id,source,symbol
		FROM raw.landings
		WHERE source='vci' AND route='equity_ohlcv'
		  AND payload_bytes IS NOT NULL AND payload_sha256 IS NOT NULL
		  AND encode(sha256(payload_bytes),'hex')=lower(payload_sha256)
	)
	SELECT s.symbol,count(DISTINCT b.trade_date)::int
	FROM core.listing_snapshots current_listing
	JOIN core.symbols s USING(symbol_id)
	JOIN core.bars_daily b ON b.symbol_id=s.symbol_id
	JOIN verified_landings r ON r.ingest_id=b.ingest_id AND r.source=b.source AND r.symbol=s.symbol
	JOIN core.calendar c ON c.trade_date=b.trade_date
	LEFT JOIN core.calendar_overrides o ON o.trade_date=b.trade_date
	WHERE current_listing.snapshot_date=$1::date
	  AND b.trade_date<$1::date AND b.source='vci' AND b.is_traded AND b.v>0
	  AND coalesce(o.is_session,c.is_session,false)
	GROUP BY s.symbol`, asOf)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	tenure := make(map[string]int)
	for rows.Next() {
		var symbol string
		var sessions int
		if err = rows.Scan(&symbol, &sessions); err != nil {
			return nil, err
		}
		tenure[symbol] = sessions
	}
	if err = rows.Err(); err != nil {
		return nil, err
	}
	return tenure, nil
}

const (
	TierAEntryRank   = 400
	TierAHoldRank    = 500
	TierAMinSessions = 250
	TierAMinADV20    = 5_000_000_000.0
	TierABars        = 20
)

var ErrTierAUnavailable = errors.New("verified Tier A selection inputs unavailable")
var ErrInvalidTierACandidate = errors.New("invalid Tier A candidate")

type TierACandidate struct {
	Symbol      string
	Median20    float64
	Average20   float64
	Rank        int
	PriorMember bool
}

type TierABuildResult struct {
	AsOf       string   `json:"as_of"`
	Sessions   []string `json:"ranking_sessions"`
	Listed     int      `json:"verified_listed_symbols"`
	Incomplete int      `json:"incomplete_symbols_excluded"`
	Selected   []string `json:"selected_symbols"`
	Inserted   bool     `json:"inserted"`
}

// RankTierA ranks a complete, already verified candidate set. Its liquidity
// values are the documented close-times-volume proxy, not source traded value.
// It admits new names at rank <=400, retains prior members through rank 500,
// and applies the stated ADV20 floor to that proxy.
func RankTierA(candidates []TierACandidate) ([]string, error) {
	items := append([]TierACandidate(nil), candidates...)
	for _, item := range items {
		if !validTierASymbol(item.Symbol) || item.Median20 < 0 || item.Average20 < 0 ||
			math.IsNaN(item.Median20) || math.IsInf(item.Median20, 0) ||
			math.IsNaN(item.Average20) || math.IsInf(item.Average20, 0) {
			return nil, fmt.Errorf("%w: %q", ErrInvalidTierACandidate, item.Symbol)
		}
	}
	sort.Slice(items, func(i, j int) bool {
		if items[i].Median20 != items[j].Median20 {
			return items[i].Median20 > items[j].Median20
		}
		return items[i].Symbol < items[j].Symbol
	})
	selected := make([]string, 0, TierAEntryRank)
	for i := range items {
		items[i].Rank = i + 1
		if items[i].Average20 < TierAMinADV20 {
			continue
		}
		if items[i].Rank <= TierAEntryRank || (items[i].PriorMember && items[i].Rank <= TierAHoldRank) {
			selected = append(selected, items[i].Symbol)
		}
	}
	return selected, nil
}

func validTierASymbol(symbol string) bool {
	if len(symbol) == 0 || len(symbol) > 12 || strings.TrimSpace(symbol) != symbol {
		return false
	}
	for _, r := range symbol {
		if !(r >= 'A' && r <= 'Z' || r >= '0' && r <= '9') {
			return false
		}
	}
	return true
}

func completeTierAWindow(values []float64) bool {
	if len(values) != TierABars {
		return false
	}
	for _, value := range values {
		if value < 0 || math.IsNaN(value) || math.IsInf(value, 0) {
			return false
		}
	}
	return true
}

// BuildTierAFromPostgres builds the membership for a date using only stored
// data. All validation and replacement occur in one repeatable-read
// transaction; any incomplete input returns without inserting membership.
func BuildTierAFromPostgres(ctx context.Context, db *sql.DB, asOf time.Time) (TierABuildResult, error) {
	var out TierABuildResult
	if ctx == nil || db == nil || asOf.IsZero() {
		return out, errors.New("context, database and date are required")
	}
	day := asOf.Format("2006-01-02")
	if parsed, err := time.Parse("2006-01-02", day); err != nil || !parsed.Equal(time.Date(asOf.Year(), asOf.Month(), asOf.Day(), 0, 0, 0, 0, time.UTC)) {
		return out, errors.New("date must be a date-only value")
	}
	out.AsOf = day
	tx, err := db.BeginTx(ctx, &sql.TxOptions{Isolation: sql.LevelRepeatableRead})
	if err != nil {
		return out, err
	}
	defer tx.Rollback()
	if _, err = tx.ExecContext(ctx, `SELECT pg_advisory_xact_lock(2108701,2602)`); err != nil {
		return out, err
	}
	var isSession bool
	if err = tx.QueryRowContext(ctx, `SELECT coalesce((SELECT is_session FROM core.calendar_overrides WHERE trade_date=$1::date),(SELECT is_session FROM core.calendar WHERE trade_date=$1::date),false)`, day).Scan(&isSession); err != nil {
		return out, err
	}
	if !isSession {
		return out, fmt.Errorf("%w: %s is not a recorded session", ErrTierAUnavailable, day)
	}

	// The dated snapshot must be complete and match its exact archived provider
	// frame, including all exchanges and delisted rows being excluded by parser.
	var listingBytes []byte
	var listingDigest string
	if err = tx.QueryRowContext(ctx, `SELECT payload_bytes,payload_sha256 FROM raw.landings
		WHERE source='vci' AND route='equity_list' AND (fetched_at AT TIME ZONE 'Asia/Ho_Chi_Minh')::date=$1::date
		ORDER BY landing_id DESC LIMIT 1`, day).Scan(&listingBytes, &listingDigest); err != nil {
		return out, fmt.Errorf("%w: dated listing landing: %v", ErrTierAUnavailable, err)
	}
	listingSum := sha256.Sum256(listingBytes)
	if len(listingBytes) < 2 || !strings.EqualFold(hex.EncodeToString(listingSum[:]), listingDigest) {
		return out, fmt.Errorf("%w: dated listing landing checksum mismatch", ErrTierAUnavailable)
	}
	listed, err := parseVerifiedListingFrame(listingBytes)
	if err != nil {
		return out, fmt.Errorf("%w: invalid dated listing frame: %v", ErrTierAUnavailable, err)
	}
	rows, err := tx.QueryContext(ctx, `SELECT s.symbol,l.exchange,coalesce(l.industry,'')
		FROM core.listing_snapshots l JOIN core.symbols s USING(symbol_id)
		WHERE l.snapshot_date=$1::date ORDER BY s.symbol`, day)
	if err != nil {
		return out, err
	}
	for i := 0; rows.Next(); i++ {
		var got listedRow
		if err = rows.Scan(&got.symbol, &got.exchange, &got.industry); err != nil {
			rows.Close()
			return out, err
		}
		if i >= len(listed) || listed[i] != got {
			rows.Close()
			return out, fmt.Errorf("%w: relational listing differs from archived frame at row %d", ErrTierAUnavailable, i)
		}
		out.Listed++
	}
	if err = rows.Err(); err != nil {
		rows.Close()
		return out, err
	}
	if err = rows.Close(); err != nil {
		return out, err
	}
	if out.Listed != len(listed) || out.Listed < 1000 {
		return out, fmt.Errorf("%w: listing frame/snapshot count differs (%d/%d)", ErrTierAUnavailable, out.Listed, len(listed))
	}

	// Use 20 distinct recorded market sessions before as-of. A symbol requires
	// one valid traded bar with a non-null derived traded-value proxy on every date.
	var sessionRows *sql.Rows
	sessionRows, err = tx.QueryContext(ctx, `WITH effective AS (
		SELECT c.trade_date,coalesce(o.is_session,c.is_session) is_session,
			('observed_bars'=ANY(string_to_array(c.source,'+'))) observed
		FROM core.calendar c LEFT JOIN core.calendar_overrides o USING(trade_date)
		WHERE c.trade_date<$1::date
		UNION ALL SELECT o.trade_date,o.is_session,false FROM core.calendar_overrides o
		LEFT JOIN core.calendar c USING(trade_date) WHERE c.trade_date<$1::date AND c.trade_date IS NULL
	), recent AS (SELECT trade_date FROM effective WHERE is_session AND observed ORDER BY trade_date DESC LIMIT 20)
	SELECT trade_date::text FROM recent ORDER BY trade_date`, day)
	if err != nil {
		return out, err
	}
	for sessionRows.Next() {
		var d string
		if err = sessionRows.Scan(&d); err != nil {
			sessionRows.Close()
			return out, err
		}
		out.Sessions = append(out.Sessions, d)
	}
	if err = sessionRows.Err(); err != nil {
		sessionRows.Close()
		return out, err
	}
	if err = sessionRows.Close(); err != nil {
		return out, err
	}
	if len(out.Sessions) != TierABars {
		return out, fmt.Errorf("%w: need %d recorded prior sessions, have %d", ErrTierAUnavailable, TierABars, len(out.Sessions))
	}

	// Tenure is a lower bound from complete, point-in-time listing snapshots.
	// A missing or corrupt historical snapshot earns no tenure credit; it does
	// not invalidate otherwise verified candidates. The as-of frame above is
	// still mandatory because it defines today's listed universe.
	tenure, err := loadVerifiedTradeTenure(ctx, tx, day)
	if err != nil {
		return out, err
	}
	eligible := tenureEligibleSymbols(listed, tenure)
	if len(eligible) == 0 {
		return out, fmt.Errorf("%w: no listed symbols have %d verified prior-session traded bars", ErrTierAUnavailable, TierAMinSessions)
	}

	priorDate := out.Sessions[len(out.Sessions)-1]
	prior := map[int64]bool{}
	rows, err = tx.QueryContext(ctx, `SELECT symbol_id FROM ops.dq_tier_a_symbols WHERE trade_date=$1::date`, priorDate)
	if err != nil {
		return out, err
	}
	for rows.Next() {
		var id int64
		if err = rows.Scan(&id); err != nil {
			rows.Close()
			return out, err
		}
		prior[id] = true
	}
	if err = rows.Err(); err != nil {
		rows.Close()
		return out, err
	}
	if err = rows.Close(); err != nil {
		return out, err
	}
	// If an earlier universe exists, the immediately prior recorded session
	// must have a membership snapshot; otherwise retention history is unknown.
	var anyPrior bool
	if err = tx.QueryRowContext(ctx, `SELECT EXISTS(SELECT 1 FROM ops.dq_tier_a_symbols WHERE trade_date<$1::date)`, day).Scan(&anyPrior); err != nil {
		return out, err
	}
	if anyPrior && len(prior) == 0 {
		return out, fmt.Errorf("%w: prior-session Tier A membership missing for hysteresis", ErrTierAUnavailable)
	}

	var candidates []TierACandidate
	args := make([]any, 0, TierABars+1+len(eligible))
	placeholders := make([]string, 0, TierABars)
	for i, session := range out.Sessions {
		args = append(args, session)
		placeholders = append(placeholders, fmt.Sprintf("$%d::date", i+1))
	}
	args = append(args, day)
	dayArg := len(args)
	eligibleMarks := make([]string, 0, len(eligible))
	for _, symbol := range eligible {
		args = append(args, symbol)
		eligibleMarks = append(eligibleMarks, fmt.Sprintf("$%d", len(args)))
	}
	eligibleClause := " AND s.symbol IN (" + strings.Join(eligibleMarks, ",") + ")"
	barQuery := fmt.Sprintf(`WITH sessions(trade_date) AS (VALUES (%s)), prior AS (
		SELECT symbol_id FROM ops.dq_tier_a_symbols WHERE trade_date=$%d::date
	)
	SELECT s.symbol_id,s.symbol,d.trade_date::text,b.trade_date::text,b.traded_value_proxy_vnd,
		(pr.symbol_id IS NOT NULL),
		EXISTS(SELECT 1 FROM ops.bar_quality_issues q JOIN ops.ingest_jobs j USING(job_id)
			WHERE q.trade_date=d.trade_date AND j.symbol=s.symbol
			AND q.category IN ('INVALID_OHLC','INVALID_PRICE','INVALID_VOLUME')),
		EXISTS(SELECT 1 FROM ops.ingest_jobs j JOIN raw.landings r ON r.landing_id=j.landed_id
		WHERE j.symbol=s.symbol AND j.route='equity_ohlcv' AND j.source=b.source AND j.state IN ('COMPLETED','PARTIAL')
			AND j.date_from<=d.trade_date AND j.date_to>=d.trade_date AND r.route='equity_ohlcv'
			AND r.source=b.source AND r.symbol=s.symbol AND r.ingest_id=b.ingest_id
			AND r.payload_bytes IS NOT NULL AND encode(sha256(r.payload_bytes),'hex')=lower(r.payload_sha256))
	FROM core.listing_snapshots l JOIN core.symbols s USING(symbol_id)
	CROSS JOIN sessions d
	LEFT JOIN core.bars_daily_with_proxy b ON b.symbol_id=s.symbol_id AND b.trade_date=d.trade_date
		AND b.source='vci' AND b.is_traded AND b.traded_value_proxy_vnd IS NOT NULL AND b.traded_value_proxy_vnd>=0
	LEFT JOIN prior pr ON pr.symbol_id=s.symbol_id
	WHERE l.snapshot_date=$%d::date%s ORDER BY s.symbol,d.trade_date`,
		strings.Join(placeholders, "),("), dayArg, dayArg, eligibleClause)
	rows, err = tx.QueryContext(ctx, barQuery, args...)
	if err != nil {
		return out, err
	}
	type barSet struct {
		values []float64
		prior  bool
	}
	bySymbol := make(map[string]barSet, out.Listed)
	incomplete := make(map[string]bool)
	seen := make(map[string]bool, len(eligible))
	for rows.Next() {
		var id int64
		var symbol, session string
		var barDate sql.NullString
		var value sql.NullFloat64
		var isPrior, hasQuality, hasSource bool
		if err = rows.Scan(&id, &symbol, &session, &barDate, &value, &isPrior, &hasQuality, &hasSource); err != nil {
			rows.Close()
			return out, err
		}
		seen[symbol] = true
		if hasQuality || !hasSource || !barDate.Valid || !value.Valid || value.Float64 < 0 || math.IsNaN(value.Float64) || math.IsInf(value.Float64, 0) {
			incomplete[symbol] = true
			continue
		}
		item := bySymbol[symbol]
		item.values = append(item.values, value.Float64)
		item.prior = isPrior || item.prior
		bySymbol[symbol] = item
	}
	if err = rows.Err(); err != nil {
		rows.Close()
		return out, err
	}
	if err = rows.Close(); err != nil {
		return out, err
	}
	if len(seen) != len(eligible) {
		return out, fmt.Errorf("%w: query rows differ from tenure-eligible listing snapshot", ErrTierAUnavailable)
	}
	for _, symbol := range eligible {
		item, ok := bySymbol[symbol]
		if incomplete[symbol] || !ok || !completeTierAWindow(item.values) {
			out.Incomplete++
			continue
		}
		sort.Float64s(item.values)
		median := item.values[9]/2 + item.values[10]/2
		average := 0.0
		for i, v := range item.values {
			average += (v - average) / float64(i+1)
		}
		candidates = append(candidates, TierACandidate{Symbol: symbol, Median20: median, Average20: average, PriorMember: item.prior})
	}
	out.Selected, err = RankTierA(candidates)
	if err != nil {
		return out, err
	}
	if len(out.Selected) == 0 {
		return out, fmt.Errorf("%w: no symbols satisfy liquidity and rank policy", ErrTierAUnavailable)
	}
	// A partial full-history job can reflect bad observations on unrelated old
	// dates. The ranking window and dated DQ gate validate each relevant session
	// directly, so only an unresolved BLOCKED job covering as-of remains a gate.
	selectedArgs := []any{day}
	selectedMarks := make([]string, 0, len(out.Selected))
	for i, symbol := range out.Selected {
		selectedArgs = append(selectedArgs, symbol)
		selectedMarks = append(selectedMarks, fmt.Sprintf("$%d", i+2))
	}
	var expectedDayPartial int
	statusQuery := fmt.Sprintf(`SELECT count(*) FROM ops.ingest_jobs
		WHERE route='equity_ohlcv' AND state='BLOCKED'
		AND (date_from IS NULL OR date_from<=$1::date) AND (date_to IS NULL OR date_to>=$1::date)
		AND symbol IN (%s)`, strings.Join(selectedMarks, ","))
	if err = tx.QueryRowContext(ctx, statusQuery, selectedArgs...).Scan(&expectedDayPartial); err != nil {
		return out, err
	}
	if expectedDayPartial > 0 {
		return out, fmt.Errorf("%w: %d selected symbol jobs are PARTIAL/BLOCKED for expected date %s", ErrTierAUnavailable, expectedDayPartial, day)
	}
	// Dated evidence is append-once. Replays are idempotent only when identical;
	// never silently replace membership after DQ results may have consumed it.
	var existing []string
	rows, err = tx.QueryContext(ctx, `SELECT s.symbol FROM ops.dq_tier_a_symbols u JOIN core.symbols s USING(symbol_id) WHERE u.trade_date=$1::date ORDER BY s.symbol`, day)
	if err != nil {
		return out, err
	}
	for rows.Next() {
		var s string
		if err = rows.Scan(&s); err != nil {
			rows.Close()
			return out, err
		}
		existing = append(existing, s)
	}
	if err = rows.Err(); err != nil {
		rows.Close()
		return out, err
	}
	if err = rows.Close(); err != nil {
		return out, err
	}
	ordered := append([]string(nil), out.Selected...)
	sort.Strings(ordered)
	if len(existing) > 0 {
		if len(existing) != len(ordered) {
			return out, fmt.Errorf("%w: dated membership already exists with different size", ErrTierAUnavailable)
		}
		for i := range existing {
			if existing[i] != ordered[i] {
				return out, fmt.Errorf("%w: dated membership is immutable", ErrTierAUnavailable)
			}
		}
		out.Inserted = false
	} else {
		for _, symbol := range ordered {
			if _, err = tx.ExecContext(ctx, `INSERT INTO ops.dq_tier_a_symbols(trade_date,symbol_id) SELECT $1::date,symbol_id FROM core.symbols WHERE symbol=$2`, day, symbol); err != nil {
				return out, err
			}
		}
		out.Inserted = true
	}
	if err = tx.Commit(); err != nil {
		return out, err
	}
	return out, nil
}
