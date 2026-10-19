// vnpipe is the offline-first single-user VN-Signal pipeline controller.
package main

import (
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

	"github.com/Kashumir-Kaiser/VN-Signal/go/internal/config"
	"github.com/Kashumir-Kaiser/VN-Signal/go/internal/ingest"
	"github.com/Kashumir-Kaiser/VN-Signal/go/internal/live"
	"github.com/Kashumir-Kaiser/VN-Signal/go/internal/migrate"
	"github.com/Kashumir-Kaiser/VN-Signal/go/internal/quota"
	"github.com/Kashumir-Kaiser/VN-Signal/go/internal/worker"
)

func usage() {
	fmt.Println(`vnpipe (bootstrap) - VN-Signal
Usage:
  vnpipe probe [--active --trading-days N] [--routes route,...] [--out DIR]
  vnpipe probe --active --trading-days N --routes company_info --symbol TICKER --out DIR
  vnpipe probe-ohlcv --active --symbol TICKER --source vci|kbs --from DATE --to DATE [--raw-prices] [--out DIR]
  vnpipe budget --daily N --monthly N --days N --rpm N
  vnpipe validate-bars --input FILE --symbol TICKER
  vnpipe preview-backfill --probe FILE --symbols FILE --from DATE --to DATE --days N
  vnpipe import-listings --probe FILE [--min-symbols N] (offline Postgres import)
  vnpipe refresh-listings --active --trading-days N [--out DIR] (one metered call, save and import)
  vnpipe refresh-company-info --active --trading-days N --symbol TICKER [--out DIR]
  vnpipe import-company-info --probe FILE (offline source-backed profile import)
  vnpipe collect-company-profiles --active --trading-days N [--max-calls N] [--out DIR]
  vnpipe company-profile-status [--limit N] (offline coverage review)
  vnpipe rebuild-security-master (offline sync of every archived VCI equity_list frame)
  vnpipe backfill-status --from DATE --to DATE [--source vci] (read-only)
  vnpipe reprocess-archived --from DATE --to DATE --source vci (offline no-quota)
  vnpipe requeue-unarchived --symbol SYMBOL --from DATE --to DATE --source vci (audited offline opt-in)
  vnpipe backfill --active --probe FILE --from DATE --to DATE --days N
  vnpipe dq-run --date YYYY-MM-DD (Postgres-backed, offline quality gate)
  vnpipe tier-a-build --date YYYY-MM-DD (offline, evidence-gated membership build)
  vnpipe select-dq-cross-source --date YYYY-MM-DD (offline, selects 30 replay-verified VCI/KBS or VCI/VNDIRECT pairs)
  vnpipe backfill-index --active --probe FILE --from DATE --to DATE --days N (one-call VNINDEX/KBS backfill)
  vnpipe ingest-kbs-cross-source --active --from DATE --to DATE --days N [--max-calls N] (audited raw-only KBS equity comparison, max 30)
  vnpipe ingest-kbs-invalid-history --active --from DATE --to DATE --days N [--max-calls N] (audited raw-only KBS histories for partial VCI symbols)
  vnpipe backfill-dnse --active --from DATE --to DATE [--symbols ABC,VCB] [--max-calls N] [--pace 500ms] (audited alternate-source historical OHLCV)
  vnpipe backfill-vndirect --active --from DATE --to DATE [--symbols ABC,VCB] [--max-calls N] [--pace 500ms] [--shard-index N --shard-count N] (audited alternate-source historical OHLCV)
  vnpipe migrate [--dir sql/migrations] (Postgres-tagged build)
  vnpipe version
Active probe requires verified absolute vnstock usage and tier status.
Unknown/percentage quota readings block active requests; CI always blocks live calls.
Historical full-universe backfill is available only as guarded opt-in; live results are unverified. Training, recommendations and the desktop app are NOT implemented.`)
}
func main() {
	if err := run(os.Args[1:]); err != nil {
		fmt.Fprintln(os.Stderr, "vnpipe:", err)
		os.Exit(1)
	}
}
func configPath() string {
	if v := os.Getenv("VNPIPE_CONFIG"); v != "" {
		return v
	}
	for _, candidate := range []string{"config/default.toml", "../config/default.toml"} {
		if _, err := os.Stat(candidate); err == nil {
			return candidate
		}
	}
	return "config/default.toml"
}
func probeRequests(endDate string) []map[string]any {
	return []map[string]any{
		{"op": "equity_list"},
		{"op": "equity_ohlcv", "symbol": "FPT", "start": "2016-01-01", "end": endDate},
		{"op": "index_ohlcv", "symbol": "VNINDEX", "start": "2016-01-01", "end": endDate},
		{"op": "income_statement", "symbol": "FPT", "period": "quarter"},
		{"op": "balance_sheet", "symbol": "FPT", "period": "quarter"},
		{"op": "cash_flow", "symbol": "FPT", "period": "quarter"},
		{"op": "market_calendar"},
	}
}

func selectProbeRequests(requests []map[string]any, routeNames string) ([]map[string]any, error) {
	if routeNames == "" {
		return requests, nil
	}
	selected := make(map[string]bool)
	for _, raw := range strings.Split(routeNames, ",") {
		route := strings.TrimSpace(raw)
		if route == "" {
			return nil, errors.New("--routes contains an empty route")
		}
		if selected[route] {
			return nil, fmt.Errorf("--routes repeats %q", route)
		}
		selected[route] = true
	}

	filtered := make([]map[string]any, 0, len(selected))
	for _, request := range requests {
		route, _ := request["op"].(string)
		if selected[route] {
			filtered = append(filtered, request)
			delete(selected, route)
		}
	}
	if selected["equity_trade_history"] {
		end := time.Now()
		start := end.AddDate(0, 0, -7)
		filtered = append(filtered, map[string]any{
			"op": "equity_trade_history", "symbol": "FPT", "source": "vci",
			"start": start.Format("2006-01-02"), "end": end.Format("2006-01-02"),
		})
		delete(selected, "equity_trade_history")
	}
	if len(selected) != 0 {
		for route := range selected {
			return nil, fmt.Errorf("unsupported probe route %q", route)
		}
	}
	if len(filtered) == 0 {
		return nil, errors.New("--routes must select at least one route")
	}
	return filtered, nil
}

func setProbeIndexSource(requests []map[string]any, source string) error {
	if source != "kbs" && source != "vci" {
		return errors.New("--index-source must be kbs or vci")
	}
	for _, request := range requests {
		if request["op"] == "index_ohlcv" {
			request["source"] = source
			return nil
		}
	}
	return errors.New("--index-source requires index_ohlcv in --routes")
}

func setProbeDateRange(requests []map[string]any, start, end string) error {
	if start == "" || end == "" {
		return errors.New("--from and --to must be supplied together")
	}
	from, err := time.Parse("2006-01-02", start)
	if err != nil {
		return errors.New("--from must be an ISO date")
	}
	to, err := time.Parse("2006-01-02", end)
	if err != nil || from.After(to) {
		return errors.New("--to must be an ISO date on or after --from")
	}
	found := false
	for _, request := range requests {
		op, _ := request["op"].(string)
		if op == "equity_ohlcv" || op == "index_ohlcv" {
			request["start"], request["end"] = start, end
			found = true
		}
	}
	if !found {
		return errors.New("--from and --to require equity_ohlcv or index_ohlcv in --routes")
	}
	return nil
}

// probeFailureType exposes only stable, non-sensitive categories. In
// particular, worker stderr is never copied into a probe report.
func probeFailureType(err error) string {
	if err == nil {
		return ""
	}
	switch {
	case errors.Is(err, context.DeadlineExceeded):
		return "WorkerTimeout"
	case errors.Is(err, context.Canceled):
		return "WorkerCanceled"
	case errors.Is(err, quota.ErrExhausted):
		return "QuotaBudgetExhausted"
	case errors.Is(err, live.ErrDisabled):
		return "LiveCallsDisabled"
	case errors.Is(err, quota.ErrUnknown):
		return "QuotaCapacityUnknown"
	}

	message := strings.ToLower(err.Error())
	switch {
	case strings.Contains(message, "worker request too large"):
		return "WorkerRequestTooLarge"
	case strings.Contains(message, "token too long"), strings.Contains(message, "worker frame exceeds maximum"):
		return "WorkerFrameTooLarge"
	case strings.Contains(message, "worker frame:"):
		return "WorkerFrameReadError"
	case strings.Contains(message, "malformed worker frame"),
		strings.Contains(message, "response id mismatch"),
		strings.Contains(message, "trailing data"),
		strings.Contains(message, "invalid success envelope"),
		strings.Contains(message, "invalid failure envelope"):
		return "WorkerProtocolError"
	case strings.Contains(message, "worker start:"):
		return "WorkerStartError"
	case strings.Contains(message, "worker exit:"):
		return "WorkerExitError"
	case strings.Contains(message, "worker returned 0 frames"):
		if strings.Contains(message, "python was not found") || strings.Contains(message, "python not found") {
			return "WorkerPythonUnavailable"
		}
		return "WorkerNoFrame"
	case strings.Contains(message, "missing worker path"),
		strings.Contains(message, "missing request id"),
		strings.Contains(message, "unconfigured gateway"),
		strings.Contains(message, "unsupported live route"):
		return "WorkerConfigurationError"
	default:
		return "WorkerOrGatewayError"
	}
}

// probeTracebackCause extracts a safe category from the final traceback line.
// The exception message and traceback remain private.
// tracebackExceptionType returns only a valid exception class identifier.
// It deliberately discards the exception message and all traceback context.
func tracebackExceptionType(message string) string {
	marker := "traceback (most recent call last):"
	start := strings.LastIndex(strings.ToLower(message), marker)
	if start < 0 {
		return ""
	}
	lines := strings.Split(message[start+len(marker):], "\n")
	for i := len(lines) - 1; i >= 0; i-- {
		line := strings.TrimSpace(lines[i])
		colon := strings.IndexByte(line, ':')
		if colon < 1 {
			continue
		}
		name := strings.TrimSpace(line[:colon])
		if dot := strings.LastIndexByte(name, '.'); dot >= 0 {
			name = name[dot+1:]
		}
		if len(name) == 0 || len(name) > 48 {
			continue
		}
		valid := true
		for j, r := range name {
			if !((r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z') || (j > 0 && r >= '0' && r <= '9') || (j > 0 && r == '_')) {
				valid = false
				break
			}
		}
		if !valid {
			continue
		}
		lowerName := strings.ToLower(name)
		if strings.HasSuffix(lowerName, "error") || strings.HasSuffix(lowerName, "exception") ||
			lowerName == "systemexit" || lowerName == "keyboardinterrupt" ||
			lowerName == "generatorexit" || lowerName == "stopiteration" {
			return name
		}
	}
	return ""
}

func probeTracebackCause(message string) string {
	marker := "traceback (most recent call last):"
	start := strings.LastIndex(message, marker)
	if start < 0 {
		return ""
	}
	classes := []struct{ name, cause string }{
		{"modulenotfounderror", "PythonDependencyError"},
		{"importerror", "PythonImportError"},
		{"memoryerror", "PythonMemoryError"},
		{"permissionerror", "PythonPermissionError"},
		{"filenotfounderror", "PythonUnhandledFileNotFoundError"},
		{"attributeerror", "PythonUnhandledAttributeError"},
		{"typeerror", "PythonUnhandledTypeError"},
		{"valueerror", "PythonUnhandledValueError"},
		{"keyerror", "PythonUnhandledKeyError"},
		{"indexerror", "PythonUnhandledIndexError"},
		{"runtimeerror", "PythonUnhandledRuntimeError"},
		{"connectionerror", "PythonUnhandledConnectionError"},
		{"timeouterror", "PythonUnhandledTimeoutError"},
		{"sslerror", "PythonUnhandledSSLError"},
		{"httperror", "PythonUnhandledHTTPError"},
		{"requestexception", "PythonUnhandledRequestError"},
		{"entitlementerror", "PythonEntitlementError"},
		{"ratelimitederror", "PythonRateLimitedError"},
		{"inputerror", "PythonInputError"},
		{"datasourceerror", "PythonDataSourceError"},
		{"dataunavailableerror", "PythonDataUnavailableError"},
		{"assertionerror", "PythonUnhandledAssertionError"},
	}
	lines := strings.Split(message[start+len(marker):], "\n")
	for i := len(lines) - 1; i >= 0; i-- {
		line := strings.TrimSpace(lines[i])
		for _, class := range classes {
			if strings.HasPrefix(line, class.name+":") || line == class.name {
				return class.cause
			}
		}
	}
	return ""
}

// probeWorkerCause maps private stderr to stable categories without including
// traceback text, vendor output, symbols, credentials or paths in reports.
func probeWorkerCause(err error) string {
	if err == nil {
		return ""
	}
	message := strings.ToLower(err.Error())
	if !strings.Contains(message, "worker exit:") && !strings.Contains(message, "worker returned 0 frames") {
		return ""
	}
	switch {
	case strings.Contains(message, "systemexit"):
		return "PythonSystemExit"
	case strings.Contains(message, "modulenotfounderror"), strings.Contains(message, "no module named"):
		return "PythonDependencyError"
	case strings.Contains(message, "importerror"):
		return "PythonImportError"
	case strings.Contains(message, "memoryerror"), strings.Contains(message, "cannot allocate memory"):
		return "PythonMemoryError"
	case strings.Contains(message, "permissionerror"):
		return "PythonPermissionError"
	case strings.Contains(message, "fatal python error"), strings.Contains(message, "segmentation fault"), strings.Contains(message, "access violation"):
		return "PythonProcessCrash"
	case strings.Contains(message, "traceback (most recent call last)"):
		if cause := probeTracebackCause(message); cause != "" {
			return cause
		}
		if exceptionType := tracebackExceptionType(err.Error()); exceptionType != "" {
			return "PythonUnhandled" + exceptionType
		}
		return "PythonUnhandledException"
	case strings.Contains(message, "python was not found"), strings.Contains(message, "python not found"):
		return "PythonUnavailable"
	default:
		return "UnknownWorkerExit"
	}
}

func probeFailureDetails(err error) map[string]any {
	details := map[string]any{"available": false, "error_type": probeFailureType(err)}
	var exitErr *exec.ExitError
	if errors.As(err, &exitErr) {
		details["exit_code"] = exitErr.ExitCode()
	}
	if cause := probeWorkerCause(err); cause != "" {
		details["worker_cause"] = cause
	}
	return details
}

// Check a saved route summary without disclosing provider exception messages,
// account usage, local paths, or authentication details.
func companyProbeRouteError(routes json.RawMessage) error {
	var report map[string]json.RawMessage
	if err := json.Unmarshal(routes, &report); err != nil {
		return fmt.Errorf("company_info route summary invalid: %w", err)
	}
	body, ok := report["company_info"]
	if !ok {
		return errors.New("company_info route missing from saved active probe")
	}
	var state struct {
		Available  bool   `json:"available"`
		Count      int    `json:"count"`
		ErrorType  string `json:"error_type"`
		ErrorCause string `json:"error_cause"`
	}
	if err := json.Unmarshal(body, &state); err != nil {
		return fmt.Errorf("company_info route status invalid: %w", err)
	}
	if !state.Available || state.Count != 1 {
		return fmt.Errorf("company_info route unavailable: error_type=%s cause=%s count=%d",
			state.ErrorType, state.ErrorCause, state.Count)
	}
	return nil
}

func run(args []string) error {
	if len(args) == 0 {
		usage()
		return nil
	}
	switch args[0] {
	case "-h", "--help", "help":
		usage()
		return nil
	case "version":
		fmt.Println("vnpipe bootstrap 0.2.0; no model/recommendations")
		return nil
	case "probe":
		f := flag.NewFlagSet("probe", flag.ContinueOnError)
		active := f.Bool("active", false, "opt in to metered vnstock route calls")
		remainingDays := f.Int("trading-days", 0, "remaining trading days in this month, mandatory for active probe")
		routeNames := f.String("routes", "", "comma-separated routes to probe (active only; default: all)")
		indexSource := f.String("index-source", "", "index_ohlcv provider for a selected probe: kbs or vci")
		probeStart := f.String("from", "", "start ISO date for selected equity_ohlcv/index_ohlcv probes")
		probeEnd := f.String("to", "", "end ISO date for selected equity_ohlcv/index_ohlcv probes")
		companySymbol := f.String("symbol", "", "company_info only: ticker whose profile to inspect")
		out := f.String("out", filepath.Join("..", "docs", "probe"), "report directory")
		if err := f.Parse(args[1:]); err != nil {
			return err
		}
		if len(f.Args()) != 0 {
			return errors.New("unexpected arguments")
		}
		routesSet := false
		f.Visit(func(fl *flag.Flag) {
			if fl.Name == "routes" {
				routesSet = true
			}
		})
		if routesSet && !*active {
			return errors.New("--routes requires --active")
		}
		if routesSet && strings.TrimSpace(*routeNames) == "" {
			return errors.New("--routes must select at least one route")
		}
		var requests []map[string]any
		if *active {
			if strings.TrimSpace(*routeNames) == "company_info" {
				sym := strings.ToUpper(strings.TrimSpace(*companySymbol))
				if len(sym) < 1 || len(sym) > 12 || sym != *companySymbol {
					return errors.New("--routes company_info requires --symbol UPPERCASE_TICKER")
				}
				for _, ch := range sym {
					if !(ch >= 'A' && ch <= 'Z' || ch >= '0' && ch <= '9') {
						return errors.New("invalid company_info ticker")
					}
				}
				requests = []map[string]any{{"op": "company_info", "symbol": sym, "source": "vci"}}
			} else {
				if *companySymbol != "" {
					return errors.New("--symbol only applies to --routes company_info")
				}
				selected, err := selectProbeRequests(probeRequests(time.Now().Format("2006-01-02")), *routeNames)
				if err != nil {
					return err
				}
				requests = selected
			}
		} else if *companySymbol != "" {
			return errors.New("--symbol requires an active company_info probe")
		}
		if *probeStart != "" || *probeEnd != "" {
			if !*active {
				return errors.New("--from and --to require an active history probe")
			}
			if err := setProbeDateRange(requests, *probeStart, *probeEnd); err != nil {
				return err
			}
		}
		if *indexSource != "" {
			if !*active {
				return errors.New("--index-source requires an active index_ohlcv probe")
			}
			if err := setProbeIndexSource(requests, *indexSource); err != nil {
				return err
			}
		}
		if _, err := config.Load(configPath()); err != nil {
			return fmt.Errorf("invalid config: %w", err)
		}
		ignored, err := loadIgnoredSymbols()
		if err != nil {
			return err
		}
		if *active {
			retained := make([]map[string]any, 0, len(requests))
			excluded := 0
			for _, req := range requests {
				op, _ := req["op"].(string)
				symbol, _ := req["symbol"].(string)
				if (op == "company_info" || op == "equity_ohlcv") && ignored[symbol] {
					excluded++
					continue
				}
				retained = append(retained, req)
			}
			if excluded > 0 {
				fmt.Printf("Probe: skipped %d ignored tickers\n", excluded)
			}
			requests = retained
			if len(requests) == 0 {
				return nil
			}
		}

		if *active && os.Getenv("VNPIPE_DISABLE_LIVE") == "1" {
			return live.ErrDisabled
		}
		ctx, cancel := context.WithTimeout(context.Background(), 3*time.Minute)
		defer cancel()
		// Passive status and usage have no market-data route; they do not consume
		// the account's quote quota. Python direct active probe is disabled.
		result, err := worker.Invoke(ctx, worker.Python(), worker.ScriptPath(), map[string]any{"id": "local-probe", "op": "probe", "active": false})
		if err != nil {
			return err
		}
		if !result.OK {
			return fmt.Errorf("worker probe error: %+v", result.Error)
		}
		var report map[string]json.RawMessage
		if err := json.Unmarshal(result.Data, &report); err != nil {
			return err
		}
		if *active {
			if *remainingDays < 1 || *remainingDays > 31 {
				return errors.New("active probe requires 1..31 remaining trading days")
			}
			daily, monthly, e := quota.ParseRemaining(report["usage"])
			if e != nil {
				return fmt.Errorf("cannot meter live probe: %w", e)
			}
			rpm, e := quota.TierRPM(report["status"], report["usage"])
			if e != nil {
				return fmt.Errorf("cannot verify tier rate: %w", e)
			}
			budget, e := quota.Budget(daily, monthly, *remainingDays)
			if e != nil {
				return e
			}
			if budget < len(requests) {
				return fmt.Errorf("insufficient conservative budget %d for %d probe calls", budget, len(requests))
			}
			pacer, e := quota.NewPacer(rpm, budget)
			if e != nil {
				return e
			}
			gateway, e := live.New(pacer, func(ctx context.Context, job map[string]any) (worker.Response, error) {
				return worker.Invoke(ctx, worker.Python(), worker.ScriptPath(), job)
			})
			if e != nil {
				return e
			}
			summary := make(map[string]any)
			for i, job := range requests {
				op := job["op"].(string)
				job["id"] = fmt.Sprintf("probe-%02d", i)
				started := time.Now()
				resp, e := gateway.Call(ctx, job)
				elapsed := time.Since(started).Milliseconds()
				if e != nil {
					details := probeFailureDetails(e)
					details["duration_ms"] = elapsed
					summary[op] = details
					continue
				}
				if !resp.OK {
					details := map[string]any{"available": false, "error_type": resp.Error.Type, "duration_ms": elapsed}
					if resp.Error.Cause != "" {
						details["error_cause"] = resp.Error.Cause
					}
					summary[op] = details
					continue
				}
				var payload struct {
					Count      int              `json:"count"`
					Columns    []string         `json:"columns"`
					Rows       []map[string]any `json:"rows"`
					Attributes map[string]any   `json:"attributes"`
				}
				// Retain successful provider data even if downstream frame
				// validation later fails. No extra vendor request is required
				// to investigate source shapes on the registered machine.
				if op == "company_info" {
					report["company_info_frame"] = append(json.RawMessage(nil), resp.Data...)
					symbolJSON, _ := json.Marshal(job["symbol"].(string))
					report["company_info_symbol"] = symbolJSON
				}
				if e := json.Unmarshal(resp.Data, &payload); e != nil {
					summary[op] = map[string]any{"available": false, "error_type": "InvalidRouteFrame", "duration_ms": elapsed}
					continue
				}
				dates := make([]string, 0, len(payload.Rows))
				for _, row := range payload.Rows {
					for _, key := range []string{"time", "date", "trading_date"} {
						if s, ok := row[key].(string); ok && s != "" {
							dates = append(dates, s)
							break
						}
					}
				}
				first, last := "", ""
				for _, d := range dates {
					if first == "" || d < first {
						first = d
					}
					if d > last {
						last = d
					}
				}
				// Preserve the SAME metered equity-list response for a later offline,
				// transactional import. No second vendor request is needed.
				if op == "equity_list" && payload.Count > 0 {
					report["listing_frame"] = append(json.RawMessage(nil), resp.Data...)
				}
				if op == "company_info" {
					symbol := job["symbol"].(string)
					matched := false
					if payload.Count == 1 && len(payload.Rows) == 1 {
						v, ok := payload.Rows[0]["symbol"].(string)
						matched = ok && strings.EqualFold(v, symbol)
					}
					hasDateColumn := false
					for _, column := range payload.Columns {
						if column == "listing_date" {
							hasDateColumn = true
							break
						}
					}
					if !matched || !hasDateColumn {
						summary[op] = map[string]any{"available": false, "error_type": "InvalidCompanyInfoFrame", "duration_ms": elapsed}
						continue
					}
					// The original frame and requested symbol were already
					// retained before validation for offline inspection.
				}

				details := map[string]any{"available": payload.Count > 0,
					"count": payload.Count, "columns": payload.Columns,
					"first_observed_date": first, "last_observed_date": last,
					"attributes": payload.Attributes, "duration_ms": elapsed}
				if op == "company_info" && payload.Count == 0 {
					details["error_type"] = "EmptyCompanyInfo"
				}
				summary[op] = details
			}
			report["active"] = json.RawMessage("true")
			encoded, _ := json.Marshal(summary)
			report["routes"] = encoded
		}
		if err := os.MkdirAll(*out, 0700); err != nil {
			return err
		}
		// Passive health checks must not overwrite the active probe's saved
		// listing frame on the same Vietnam trading date.
		nameSuffix := ".json"
		if !*active {
			nameSuffix = ".passive.json"
		}
		vietnamToday := time.Now().In(time.FixedZone("Asia/Ho_Chi_Minh", 7*3600)).Format("2006-01-02")
		name := filepath.Join(*out, vietnamToday+nameSuffix)
		pretty, err := json.MarshalIndent(report, "", "  ")
		if err != nil {
			return err
		}
		if err := os.WriteFile(name, append(pretty, '\n'), 0600); err != nil {
			return err
		}
		fmt.Printf("Probe report: %s (active=%v). Does NOT certify entitlements.\n", name, *active)
		if *active && len(requests) == 1 && requests[0]["op"] == "company_info" {
			if routeErr := companyProbeRouteError(report["routes"]); routeErr != nil {
				return fmt.Errorf("%w; saved report=%s", routeErr, name)
			}
		}
		return nil
	case "probe-ohlcv":
		return runProbeOHLCV(args[1:])
	case "migrate":
		f := flag.NewFlagSet("migrate", flag.ContinueOnError)
		dir := f.String("dir", "sql/migrations", "numbered migrations folder")
		if err := f.Parse(args[1:]); err != nil {
			return err
		}
		if len(f.Args()) != 0 {
			return errors.New("unexpected migration arguments")
		}
		// Historical source backfills can touch millions of archived observations.
		ctx, cancel := context.WithTimeout(context.Background(), 30*time.Minute)
		defer cancel()
		db, err := openPostgres(ctx, os.Getenv("DATABASE_URL"))
		if err != nil {
			return err
		}
		defer db.Close()
		count, err := migrate.Apply(ctx, db, *dir)
		if err != nil {
			return err
		}
		fmt.Printf("PostgreSQL migrations applied: %d (existing checked by SHA-256)\n", count)
		return nil
	case "dq-run":
		return runDQGate(args[1:])
	case "tier-a-build":
		return runTierABuild(args[1:])
	case "select-dq-cross-source":
		return runSelectDQCrossSource(args[1:])
	case "backfill-index":
		return runIndexBackfill(args[1:])
	case "ingest-kbs-cross-source":
		return runKBSCrossSource(args[1:])
	case "ingest-kbs-invalid-history":
		return runKBSInvalidHistory(args[1:])
	case "backfill-dnse":
		return runDNSEBackfill(args[1:])
	case "backfill-vndirect":
		return runVNDIRECTBackfill(args[1:])
	case "import-listings":
		return runImportListings(args[1:])
	case "refresh-listings":
		return runRefreshListings(args[1:])
	case "import-company-info":
		return runImportCompanyInfo(args[1:])
	case "collect-company-profiles":
		return runProfileBatch(args[1:])
	case "company-profile-status":
		return runProfileStatus(args[1:])
	case "refresh-company-info":
		return runRefreshCompanyInfo(args[1:])
	case "rebuild-security-master":
		return runRebuildSecurityMaster(args[1:])
	case "backfill-status":
		return runBackfillStatus(args[1:])
	case "reprocess-archived":
		return runReprocessArchived(args[1:])
	case "requeue-unarchived":
		return runRequeueUnarchived(args[1:])
	case "backfill":
		return runBackfill(args[1:])
	case "preview-backfill":
		f := flag.NewFlagSet("preview-backfill", flag.ContinueOnError)
		probeFile := f.String("probe", "", "locally recorded active probe report")
		symbolFile := f.String("symbols", "", "JSON array of current listed symbols (not a live call)")
		start := f.String("from", "", "earliest requested history YYYY-MM-DD")
		end := f.String("to", "", "latest requested history YYYY-MM-DD")
		days := f.Int("days", 0, "remaining trading sessions this month")
		if err := f.Parse(args[1:]); err != nil {
			return err
		}
		if *probeFile == "" || *symbolFile == "" || len(f.Args()) != 0 {
			return errors.New("--probe and --symbols are required")
		}
		if _, err := config.Load(configPath()); err != nil {
			return err
		}
		probe, err := os.ReadFile(*probeFile)
		if err != nil {
			return err
		}
		raw, err := os.ReadFile(*symbolFile)
		if err != nil {
			return err
		}
		var symbols []string
		if err := json.Unmarshal(raw, &symbols); err != nil {
			return err
		}
		ignored, err := loadIgnoredSymbols()
		if err != nil {
			return err
		}
		symbols, _ = filterIgnoredSymbols(symbols, ignored)
		p, err := ingest.PlanBackfill(probe, *days, *start, *end, symbols, nil)
		if err != nil {
			return err
		}
		return json.NewEncoder(os.Stdout).Encode(p)
	case "validate-bars":
		f := flag.NewFlagSet("validate-bars", flag.ContinueOnError)
		input := f.String("input", "", "saved, successful Python worker data frame JSON")
		symbol := f.String("symbol", "", "ticker to bind to all parsed rows")
		if err := f.Parse(args[1:]); err != nil {
			return err
		}
		if *input == "" || *symbol == "" || len(f.Args()) != 0 {
			return errors.New("--input and --symbol are required")
		}
		file, err := os.Open(*input)
		if err != nil {
			return err
		}
		defer file.Close()
		raw, err := io.ReadAll(io.LimitReader(file, 10*1024*1024+1))
		if err != nil {
			return err
		}
		result, err := ingest.NormalizeBars(*symbol, raw)
		if err != nil {
			return err
		}
		// Do not print full historical price data: output only safe validation summary.
		return json.NewEncoder(os.Stdout).Encode(map[string]any{"symbol": result.Symbol, "rows": result.Count, "first_date": result.FirstDate, "last_date": result.LastDate, "validation": "passed"})
	case "budget":
		f := flag.NewFlagSet("budget", flag.ContinueOnError)
		daily := f.Int("daily", -1, "absolute daily calls remaining")
		monthly := f.Int("monthly", -1, "absolute monthly calls remaining")
		days := f.Int("days", -1, "trading days remaining")
		rpm := f.Int("rpm", 0, "verified tier RPM")
		if err := f.Parse(args[1:]); err != nil {
			return err
		}
		if len(f.Args()) > 0 {
			return errors.New("unexpected arguments")
		}
		if _, err := config.Load(configPath()); err != nil {
			return fmt.Errorf("invalid config: %w", err)
		}
		b, err := quota.Budget(*daily, *monthly, *days)
		if err != nil {
			return err
		}
		if *rpm < 1 || *rpm > 60 {
			return errors.New("RPM must be a verified value between 1 and 60")
		}
		if _, err := quota.NewPacer(*rpm, b); err != nil {
			return err
		}
		fmt.Printf("Maximum planned calls today: %d; pacing 85%% of %d verified req/min\n", b, *rpm)
		return nil
	default:
		return fmt.Errorf("unknown command %q", args[0])
	}
}
