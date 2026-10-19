#!/usr/bin/env python3
"""Archive independent CafeF OHLCV around every VNDIRECT conflict date.

This is a read-only research audit. It retains the provider response and hash
so each comparison can be traced to the source. CafeF is a cross-check; official
VSDC notices and exchange rules remain the primary corporate-action evidence.
"""

from __future__ import annotations

import csv
import hashlib
import json
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import date, timedelta
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen


ROOT = Path(__file__).resolve().parent
INPUT = ROOT / "reference-snapshot-audit.csv"
RAW = ROOT / "cafef-candidate-pages"
FETCHES = ROOT / "cafef-candidate-fetches.csv"
OUTPUT = ROOT / "cafef-candidate-bars.csv"
BASE = "https://cafef.vn/du-lieu/Ajax/PageNew/DataHistory/PriceHistory.ashx"
USER_AGENT = "Mozilla/5.0 (compatible; VN-Signal historical-price audit)"


def fetch(candidate: dict[str, str]) -> tuple[dict[str, str], bytes]:
    ticker = candidate["ticker"].upper()
    target = date.fromisoformat(candidate["trade_date"])
    path = RAW / f"{ticker}-{target.isoformat()}.json"
    if path.exists() and path.stat().st_size:
        body = path.read_bytes()
        return ({"ticker": ticker, "candidate_date": target.isoformat(), "http_status": "CACHE",
                 "request_url": "", "raw_file": path.name,
                 "response_sha256": hashlib.sha256(body).hexdigest(), "response_bytes": str(len(body)),
                 "error": ""}, body)

    # CafeF expects MM/DD/YYYY; other common date formats silently return the
    # default latest-page response instead of the requested historical window.
    start = (target - timedelta(days=8)).strftime("%m/%d/%Y")
    end = (target + timedelta(days=1)).strftime("%m/%d/%Y")
    query = urlencode({"Symbol": ticker, "StartDate": start, "EndDate": end,
                       "PageIndex": 1, "PageSize": 100})
    url = BASE + "?" + query
    error = ""
    for attempt in range(4):
        try:
            request = Request(url, headers={
                "User-Agent": USER_AGENT,
                "Accept": "application/json, text/plain, */*",
                "Referer": "https://cafef.vn/",
            })
            with urlopen(request, timeout=25) as response:
                body = response.read()
                status = str(response.status)
            path.write_bytes(body)
            return ({"ticker": ticker, "candidate_date": target.isoformat(), "http_status": status,
                     "request_url": url, "raw_file": path.name,
                     "response_sha256": hashlib.sha256(body).hexdigest(), "response_bytes": str(len(body)),
                     "error": ""}, body)
        except HTTPError as exc:
            error = f"HTTPError: {exc.code} {exc.reason}"
            if exc.code not in (408, 425, 429, 500, 502, 503, 504):
                break
            if attempt < 3:
                time.sleep(0.5 * (attempt + 1))
        except (URLError, TimeoutError, OSError) as exc:
            error = f"{type(exc).__name__}: {exc}"
            if attempt < 3:
                time.sleep(0.5 * (attempt + 1))
    return ({"ticker": ticker, "candidate_date": target.isoformat(), "http_status": "ERROR",
             "request_url": url, "raw_file": "", "response_sha256": "", "response_bytes": "",
             "error": error}, b"")


def parse_rows(meta: dict[str, str], body: bytes) -> list[dict[str, str]]:
    if not body:
        return []
    payload = json.loads(body.decode("utf-8", "replace"))
    data = payload.get("Data")
    if not isinstance(data, dict) or not isinstance(data.get("Data"), list):
        return []
    candidate_date = date.fromisoformat(meta["candidate_date"])
    output: list[dict[str, str]] = []
    for row in data["Data"]:
        day = date.strptime(row["Ngay"], "%d/%m/%Y") if hasattr(date, "strptime") else None
        if day is None:
            from datetime import datetime
            day = datetime.strptime(row["Ngay"], "%d/%m/%Y").date()
        output.append({
            "ticker": meta["ticker"],
            "candidate_date": candidate_date.isoformat(),
            "bar_date": day.isoformat(),
            "delta_calendar_days": str((day - candidate_date).days),
            "close": str(row.get("GiaDongCua", "")),
            "adjusted_close": str(row.get("GiaDieuChinh", "")),
            "open": str(row.get("GiaMoCua", "")),
            "high": str(row.get("GiaCaoNhat", "")),
            "low": str(row.get("GiaThapNhat", "")),
            "matched_volume": str(row.get("KhoiLuongKhopLenh", "")),
            "total_volume": str((row.get("KhoiLuongKhopLenh") or 0) + (row.get("KLThoaThuan") or 0)),
            "request_url": meta["request_url"],
            "response_sha256": meta["response_sha256"],
            "raw_file": meta["raw_file"],
        })
    return output


def write_csv(path: Path, fields: list[str], rows: list[dict[str, str]]) -> None:
    with path.open("w", encoding="utf-8-sig", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)


def main() -> int:
    RAW.mkdir(parents=True, exist_ok=True)
    with INPUT.open(encoding="utf-8-sig", newline="") as stream:
        candidates = list(csv.DictReader(stream))
    results: dict[tuple[str, str], tuple[dict[str, str], bytes]] = {}
    with ThreadPoolExecutor(max_workers=6) as pool:
        futures = {pool.submit(fetch, row): (row["ticker"].upper(), row["trade_date"])
                   for row in candidates}
        for future in as_completed(futures):
            results[futures[future]] = future.result()

    fetch_rows: list[dict[str, str]] = []
    bar_rows: list[dict[str, str]] = []
    for candidate in candidates:
        key = (candidate["ticker"].upper(), candidate["trade_date"])
        meta, body = results[key]
        fetch_rows.append(meta)
        try:
            bar_rows.extend(parse_rows(meta, body))
        except (ValueError, TypeError, KeyError, json.JSONDecodeError) as exc:
            meta["http_status"] = "PARSE_ERROR"
            meta["error"] = f"{type(exc).__name__}: {exc}"
    write_csv(FETCHES, ["ticker", "candidate_date", "http_status", "request_url", "raw_file",
                        "response_sha256", "response_bytes", "error"], fetch_rows)
    write_csv(OUTPUT, ["ticker", "candidate_date", "bar_date", "delta_calendar_days", "close",
                       "adjusted_close", "open", "high", "low", "matched_volume", "total_volume",
                       "request_url", "response_sha256", "raw_file"], bar_rows)
    errors = sum(row["http_status"] in {"ERROR", "PARSE_ERROR"} for row in fetch_rows)
    exact = {(row["ticker"], row["candidate_date"]) for row in bar_rows
             if row["bar_date"] == row["candidate_date"]}
    print(f"candidates={len(candidates)} fetch_errors={errors} exact_daily_bars={len(exact)} "
          f"archived_bars={len(bar_rows)}")
    print(f"wrote {FETCHES} and {OUTPUT}; archived source responses in {RAW}")
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
