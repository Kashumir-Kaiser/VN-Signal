#!/usr/bin/env python3
"""Archive Yahoo Finance chart events around every reference conflict candidate.

Yahoo is used as an independent cross-check only. Official VSDC notices and
exchange price references remain the primary source for resolution factors.
The script is an offline artifact reader after the first successful fetch and
never participates in hosted CI or the ingestion path.
"""

from __future__ import annotations

import csv
import hashlib
import json
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


ROOT = Path(__file__).resolve().parent
INPUT = ROOT / "reference-snapshot-audit.csv"
RAW = ROOT / "yahoo-chart-candidates"
FETCHES = ROOT / "yahoo-candidate-fetches.csv"
OUTPUT = ROOT / "yahoo-candidate-event-crosscheck.csv"
BASE = "https://query1.finance.yahoo.com/v8/finance/chart/{symbol}"
USER_AGENT = "Mozilla/5.0 (compatible; VN-Signal historical adjustment audit)"


def get_page(candidate: dict[str, str]) -> tuple[dict[str, str], bytes]:
    ticker = candidate["ticker"].upper()
    day = date.fromisoformat(candidate["trade_date"])
    symbol = f"{ticker}.VN"
    path = RAW / f"{ticker}-{day.isoformat()}.json"
    if path.exists() and path.stat().st_size:
        body = path.read_bytes()
        return {"ticker": ticker, "candidate_date": day.isoformat(), "symbol": symbol,
                "status": "CACHE", "url": BASE.format(symbol=symbol), "raw_file": path.name,
                "sha256": hashlib.sha256(body).hexdigest(), "bytes": str(len(body)), "error": ""}, body

    start = int(datetime.combine(day - timedelta(days=7), datetime.min.time(), tzinfo=timezone.utc).timestamp())
    end = int(datetime.combine(day + timedelta(days=8), datetime.min.time(), tzinfo=timezone.utc).timestamp())
    url = BASE.format(symbol=symbol) + f"?period1={start}&period2={end}&interval=1d&events=div%2Csplits"
    error = ""
    for attempt in range(4):
        try:
            request = Request(url, headers={"User-Agent": USER_AGENT, "Accept": "application/json"})
            with urlopen(request, timeout=25) as response:
                body = response.read()
                status = str(response.status)
            path.write_bytes(body)
            return {"ticker": ticker, "candidate_date": day.isoformat(), "symbol": symbol,
                    "status": status, "url": url, "raw_file": path.name,
                    "sha256": hashlib.sha256(body).hexdigest(), "bytes": str(len(body)), "error": ""}, body
        except (HTTPError, URLError, TimeoutError, OSError) as exc:
            error = f"{type(exc).__name__}: {exc}"
            if attempt < 3:
                time.sleep(0.5 * (attempt + 1))
    return {"ticker": ticker, "candidate_date": day.isoformat(), "symbol": symbol,
            "status": "ERROR", "url": url, "raw_file": "", "sha256": "", "bytes": "", "error": error}, b""


def as_date(timestamp: int) -> date:
    return datetime.fromtimestamp(timestamp, timezone.utc).date()


def summarize(candidate: dict[str, str], body: bytes) -> dict[str, str]:
    ticker = candidate["ticker"].upper()
    target = date.fromisoformat(candidate["trade_date"])
    record: dict[str, object] = json.loads(body.decode("utf-8", "replace"))
    chart = record.get("chart") or {}
    result = (chart.get("result") or [None])[0]
    err = chart.get("error")
    if result is None:
        return {"ticker": ticker, "candidate_date": target.isoformat(), "coverage": "NO_RESULT",
                "chart_error": json.dumps(err, ensure_ascii=False, separators=(",", ":")) if err else "",
                "session_date": "", "previous_session_date": "", "close": "", "previous_close": "",
                "cash_factor": "", "split_factor": "", "yahoo_event_factor": "",
                "dividend_events": "[]", "split_events": "[]"}

    timestamps = result.get("timestamp") or []
    quote = ((result.get("indicators") or {}).get("quote") or [{}])[0]
    closes = quote.get("close") or []
    adj_list = ((result.get("indicators") or {}).get("adjclose") or [{}])[0].get("adjclose") or []
    by_date: dict[date, tuple[float | None, float | None]] = {}
    for index, timestamp in enumerate(timestamps):
        day = as_date(timestamp)
        close = closes[index] if index < len(closes) else None
        adj = adj_list[index] if index < len(adj_list) else None
        by_date[day] = (close, adj)
    day_rows = sorted(by_date.items())
    on_or_before = [(d, value) for d, value in day_rows if d <= target]
    after = [(d, value) for d, value in day_rows if d >= target]
    current = next((item for item in after if item[0] == target), None)
    previous = on_or_before[-2] if len(on_or_before) >= 2 else None

    events = result.get("events") or {}
    divs = events.get("dividends") or {}
    splits = events.get("splits") or {}
    exact_divs = {str(k): v for k, v in divs.items() if as_date(int(k)) == target}
    exact_splits = {str(k): v for k, v in splits.items() if as_date(int(k)) == target}
    cash_factor = 1.0
    if previous and current:
        prev_close, prev_adj = previous[1]
        curr_close, curr_adj = current[1]
        if prev_close and curr_close and prev_adj is not None and curr_adj is not None:
            prev_adj_ratio = prev_adj / prev_close
            curr_adj_ratio = curr_adj / curr_close
            if curr_adj_ratio:
                cash_factor = prev_adj_ratio / curr_adj_ratio
    split_factor = 1.0
    for split in exact_splits.values():
        numerator = float(split.get("numerator", 0) or 0)
        denominator = float(split.get("denominator", 0) or 0)
        if numerator > 0 and denominator > 0:
            split_factor *= denominator / numerator
    event_factor = cash_factor * split_factor
    return {
        "ticker": ticker,
        "candidate_date": target.isoformat(),
        "coverage": "EXACT_SESSION" if current else "NO_EXACT_SESSION",
        "chart_error": "",
        "session_date": current[0].isoformat() if current else "",
        "previous_session_date": previous[0].isoformat() if previous else "",
        "close": str(current[1][0]) if current and current[1][0] is not None else "",
        "previous_close": str(previous[1][0]) if previous and previous[1][0] is not None else "",
        "cash_factor": f"{cash_factor:.12g}",
        "split_factor": f"{split_factor:.12g}",
        "yahoo_event_factor": f"{event_factor:.12g}",
        "dividend_events": json.dumps(exact_divs, ensure_ascii=False, separators=(",", ":")),
        "split_events": json.dumps(exact_splits, ensure_ascii=False, separators=(",", ":")),
    }


def write_csv(path: Path, fields: list[str], rows: list[dict[str, str]]) -> None:
    with path.open("w", encoding="utf-8-sig", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)


def main() -> int:
    RAW.mkdir(parents=True, exist_ok=True)
    with INPUT.open(encoding="utf-8-sig", newline="") as stream:
        candidates = list(csv.DictReader(stream))
    with (ROOT / "vsdc-event-notice-index.csv").open(encoding="utf-8-sig", newline="") as stream:
        notices = list(csv.DictReader(stream))
    action_keys = {(row["ticker"].upper(), row["candidate_date"]) for row in notices}
    # AAM's 2019 cash dividend was verified from VSDC notice 57234 but the
    # calendar crawler did not return it in the candidate-linked notice index.
    action_keys.add(("AAM", "2019-07-10"))
    candidates = [row for row in candidates
                  if (row["ticker"].upper(), row["trade_date"]) in action_keys]
    if len({(row["ticker"].upper(), row["trade_date"]) for row in candidates}) != len(action_keys):
        missing = sorted(action_keys - {(row["ticker"].upper(), row["trade_date"]) for row in candidates})
        raise RuntimeError(f"officially verified action candidates missing from audit: {missing}")
    fetched: dict[tuple[str, str], tuple[dict[str, str], bytes]] = {}
    with ThreadPoolExecutor(max_workers=6) as pool:
        futures = {pool.submit(get_page, row): (row["ticker"].upper(), row["trade_date"])
                   for row in candidates}
        for future in as_completed(futures):
            fetched[futures[future]] = future.result()

    fetch_rows = [value[0] for _, value in sorted(fetched.items())]
    crosscheck_rows: list[dict[str, str]] = []
    for candidate in candidates:
        key = (candidate["ticker"].upper(), candidate["trade_date"])
        meta, body = fetched[key]
        if body:
            summary = summarize(candidate, body)
        else:
            summary = {"ticker": key[0], "candidate_date": key[1], "coverage": "FETCH_ERROR",
                       "chart_error": meta["error"], "session_date": "", "previous_session_date": "",
                       "close": "", "previous_close": "", "cash_factor": "", "split_factor": "",
                       "yahoo_event_factor": "", "dividend_events": "[]", "split_events": "[]"}
        crosscheck_rows.append({
            **summary,
            "source_exchange": candidate["exchange_code"],
            "model_factor": candidate["model_factor"],
            "snapshot_event_factor": candidate["snapshot_event_factor"],
            "audit_last_traded_date": candidate["last_traded_date"],
            "http_status": meta["status"],
            "request_url": meta["url"],
            "response_sha256": meta["sha256"],
            "raw_file": meta["raw_file"],
        })
    write_csv(FETCHES, ["ticker", "candidate_date", "symbol", "status", "url", "raw_file", "sha256", "bytes", "error"], fetch_rows)
    write_csv(OUTPUT, [
        "ticker", "candidate_date", "source_exchange", "model_factor", "snapshot_event_factor",
        "coverage", "session_date", "previous_session_date", "close", "previous_close",
        "cash_factor", "split_factor", "yahoo_event_factor", "dividend_events", "split_events",
        "audit_last_traded_date", "http_status", "request_url", "response_sha256", "raw_file", "chart_error",
    ], crosscheck_rows)
    print(f"candidates={len(candidates)} fetch_errors={sum(row['status']=='ERROR' for row in fetch_rows)}")
    print(f"exact_sessions={sum(row['coverage']=='EXACT_SESSION' for row in crosscheck_rows)} "
          f"corporate_action_events={sum(row['dividend_events']!='[]' or row['split_events']!='[]' for row in crosscheck_rows)}")
    return 1 if any(row["status"] == "ERROR" for row in fetch_rows) else 0


if __name__ == "__main__":
    raise SystemExit(main())
