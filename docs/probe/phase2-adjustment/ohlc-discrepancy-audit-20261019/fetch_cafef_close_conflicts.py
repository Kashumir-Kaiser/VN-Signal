#!/usr/bin/env python3
"""Cross-check VNDIRECT close/range observations against CafeF history.

This preserves the source rows and public responses. It does not decide that
an open or close outside the reported high/low is invalid by itself.
"""

from __future__ import annotations

import csv
import hashlib
import json
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import date, datetime, timedelta
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen


ROOT = Path(__file__).resolve().parent
PHASE2 = ROOT.parent
VIOLATIONS = ROOT / "vndirect-violations.csv"
EXISTING_BARS = PHASE2 / "cafef-candidate-bars.csv"
EXISTING_FETCHES = PHASE2 / "cafef-candidate-fetches.csv"
RAW = ROOT / "cafef-close-range-pages"
FETCHES = ROOT / "cafef-close-range-fetches.csv"
OUTPUT = ROOT / "cafef-close-range-crosscheck.csv"
BASE = "https://cafef.vn/du-lieu/Ajax/PageNew/DataHistory/PriceHistory.ashx"
USER_AGENT = "Mozilla/5.0 (compatible; VN-Signal historical-price audit)"


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open(encoding="utf-8-sig", newline="") as stream:
        return list(csv.DictReader(stream))


def write_csv(path: Path, fields: list[str], rows: list[dict[str, str]]) -> None:
    with path.open("w", encoding="utf-8-sig", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)


def parse_day(value: str) -> date:
    return datetime.strptime(value, "%d/%m/%Y").date()


def fetch(candidate: dict[str, str]) -> tuple[dict[str, str], bytes]:
    ticker = candidate["symbol"].upper()
    target = date.fromisoformat(candidate["trade_date"])
    path = RAW / f"{ticker}-{target.isoformat()}.json"
    start = (target - timedelta(days=8)).strftime("%m/%d/%Y")
    end = (target + timedelta(days=1)).strftime("%m/%d/%Y")
    query = urlencode({"Symbol": ticker, "StartDate": start, "EndDate": end,
                       "PageIndex": 1, "PageSize": 100})
    url = BASE + "?" + query
    if path.exists() and path.stat().st_size:
        body = path.read_bytes()
        return ({"ticker": ticker, "trade_date": target.isoformat(), "http_status": "CACHE",
                 "request_url": url, "raw_file": path.name,
                 "response_sha256": hashlib.sha256(body).hexdigest(),
                 "response_bytes": str(len(body)), "error": ""}, body)

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
            return ({"ticker": ticker, "trade_date": target.isoformat(), "http_status": status,
                     "request_url": url, "raw_file": path.name,
                     "response_sha256": hashlib.sha256(body).hexdigest(),
                     "response_bytes": str(len(body)), "error": ""}, body)
        except HTTPError as exc:
            error = f"HTTPError: {exc.code} {exc.reason}"
            if exc.code not in (408, 425, 429, 500, 502, 503, 504):
                break
        except (URLError, TimeoutError, OSError) as exc:
            error = f"{type(exc).__name__}: {exc}"
        if attempt < 3:
            time.sleep(0.5 * (attempt + 1))
    return ({"ticker": ticker, "trade_date": target.isoformat(), "http_status": "ERROR",
             "request_url": url, "raw_file": "", "response_sha256": "",
             "response_bytes": "", "error": error}, b"")


def exact_rows(body: bytes, target: date) -> list[dict[str, str]]:
    if not body:
        return []
    payload = json.loads(body.decode("utf-8-sig", "replace"))
    data = payload.get("Data")
    if not isinstance(data, dict) or not isinstance(data.get("Data"), list):
        return []
    return [row for row in data["Data"] if parse_day(row["Ngay"]) == target]


def main() -> int:
    RAW.mkdir(parents=True, exist_ok=True)
    raw_rows = read_csv(VIOLATIONS)
    # Limit the focused check to close/high/low conflicts. Open/range cases are
    # retained under the Vietnamese auction-aware interpretation already
    # documented in the parent audit.
    candidates = [row for row in raw_rows
                  if float(row["c"]) < float(row["l"]) or float(row["c"]) > float(row["h"])]

    existing: dict[tuple[str, str], dict[str, str]] = {}
    if EXISTING_BARS.exists():
        for row in read_csv(EXISTING_BARS):
            key = (row["ticker"].upper(), row["bar_date"])
            existing.setdefault(key, row)

    pending = [row for row in candidates
               if (row["symbol"].upper(), row["trade_date"]) not in existing]
    network_requests = sum(
        not (RAW / f"{row['symbol'].upper()}-{row['trade_date']}.json").exists()
        for row in pending
    )
    fetched: dict[tuple[str, str], tuple[dict[str, str], bytes]] = {}
    with ThreadPoolExecutor(max_workers=4) as pool:
        futures = {pool.submit(fetch, row): (row["symbol"].upper(), row["trade_date"])
                   for row in pending}
        for future in as_completed(futures):
            fetched[futures[future]] = future.result()

    fetch_by_key: dict[tuple[str, str], dict[str, str]] = {}
    for row in candidates:
        key = (row["symbol"].upper(), row["trade_date"])
        if key in fetched:
            meta, _ = fetched[key]
            meta["ticker"], meta["trade_date"] = key
            meta["archive_location"] = f"cafef-close-range-pages/{meta['raw_file']}" if meta["raw_file"] else ""
            fetch_by_key[key] = meta
        else:
            old = existing[key]
            fetch_by_key[key] = {
                "ticker": key[0], "trade_date": key[1], "http_status": "EXISTING_ARCHIVE",
                "request_url": old.get("request_url", ""),
                "raw_file": old.get("raw_file", ""),
                "response_sha256": old.get("response_sha256", ""),
                "response_bytes": "", "error": "",
                "archive_location": f"../cafef-candidate-pages/{old.get('raw_file', '')}",
            }

    fetch_rows = [fetch_by_key[(row["symbol"].upper(), row["trade_date"])] for row in candidates]
    fetch_meta = { (row["ticker"], row["trade_date"]): row for row in fetch_rows }
    cross_rows: list[dict[str, str]] = []
    for raw in candidates:
        key = (raw["symbol"].upper(), raw["trade_date"])
        meta = fetch_meta[key]
        if key in existing:
            old = existing[key]
            bars = [{
                "GiaMoCua": old.get("open", ""), "GiaCaoNhat": old.get("high", ""),
                "GiaThapNhat": old.get("low", ""), "GiaDongCua": old.get("close", ""),
                "GiaDieuChinh": old.get("adjusted_close", ""),
                "KhoiLuongKhopLenh": old.get("matched_volume", ""),
                "KLThoaThuan": "",
            }]
        else:
            _, body = fetched[key]
            try:
                bars = exact_rows(body, date.fromisoformat(raw["trade_date"]))
            except (ValueError, TypeError, KeyError, json.JSONDecodeError):
                bars = []

        bar = bars[0] if bars else {}
        matched_volume = bar.get("KhoiLuongKhopLenh", "")
        total_volume = bar.get("KLThoaThuan", "")
        cross_rows.append({
            "symbol": raw["symbol"], "trade_date": raw["trade_date"],
            "vndirect_o": raw["o"], "vndirect_h": raw["h"],
            "vndirect_l": raw["l"], "vndirect_c": raw["c"],
            "vndirect_volume": raw["v"], "vndirect_is_traded": raw["is_traded"],
            "vndirect_adjusted_o": raw["adjusted_o"], "vndirect_adjusted_h": raw["adjusted_h"],
            "vndirect_adjusted_l": raw["adjusted_l"], "vndirect_adjusted_c": raw["adjusted_c"],
            "cafef_o": str(bar.get("GiaMoCua", "")),
            "cafef_h": str(bar.get("GiaCaoNhat", "")),
            "cafef_l": str(bar.get("GiaThapNhat", "")),
            "cafef_c": str(bar.get("GiaDongCua", "")),
            "cafef_adjusted_c": str(bar.get("GiaDieuChinh", "")),
            "cafef_matched_volume": str(matched_volume),
            "cafef_negotiated_volume": str(total_volume),
            "cafef_request_url": meta["request_url"],
            "cafef_response_sha256": meta["response_sha256"],
            "cafef_archive_location": meta["archive_location"],
            "cafef_status": "MATCHED" if bars else (
                "NO_EXACT_DATE" if meta["http_status"] not in {"ERROR", "PARSE_ERROR"}
                else "FETCH_ERROR"
            ),
        })

    write_csv(FETCHES, ["ticker", "trade_date", "http_status", "request_url", "raw_file",
                        "response_sha256", "response_bytes", "error", "archive_location"], fetch_rows)
    fields = list(cross_rows[0]) if cross_rows else []
    write_csv(OUTPUT, fields, cross_rows)
    matched = sum(row["cafef_status"] == "MATCHED" for row in cross_rows)
    errors = sum(row["http_status"] == "ERROR" for row in fetch_rows)
    print(f"close_range_rows={len(candidates)} exact_date_matches={matched} network_requests={network_requests} errors={errors}")
    print(f"wrote {OUTPUT} and {FETCHES}; archived new responses in {RAW}")
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
