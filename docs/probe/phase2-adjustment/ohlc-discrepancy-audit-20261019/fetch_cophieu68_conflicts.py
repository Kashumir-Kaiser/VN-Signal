#!/usr/bin/env python3
"""Cross-check VNDIRECT OHLC-envelope conflicts against public Cophieu68 history.

The script is an evidence collector only. It does not edit PostgreSQL or replace
the archived VNDIRECT source payloads. Every fetched HTML page is retained and
hashed so each resulting comparison can be reproduced.
"""

from __future__ import annotations

import csv
import hashlib
import re
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import date, datetime
from html.parser import HTMLParser
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen


ROOT = Path(__file__).resolve().parent
INPUT = ROOT / "vndirect-violations.csv"
RAW = ROOT / "cophieu68-pages"
FETCHES = ROOT / "cophieu68-fetches.csv"
OUTPUT = ROOT / "cophieu68-crosscheck.csv"
BASE = "https://cophieu68.vn/quote/history.php"
USER_AGENT = "Mozilla/5.0 (compatible; VN-Signal historical OHLC audit)"
MAX_PAGE = 256
MAX_WORKERS = 4


class HistoryParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.in_row = False
        self.in_cell = False
        self.cell_parts: list[str] = []
        self.cells: list[str] = []
        self.rows: list[dict[str, str]] = []

    def handle_starttag(self, tag: str, _attrs: list[tuple[str, str | None]]) -> None:
        tag = tag.lower()
        if tag == "tr":
            self.in_row = True
            self.cells = []
        elif tag == "td" and self.in_row:
            self.in_cell = True
            self.cell_parts = []

    def handle_data(self, data: str) -> None:
        if self.in_cell:
            self.cell_parts.append(data)

    def handle_endtag(self, tag: str) -> None:
        tag = tag.lower()
        if tag == "td" and self.in_cell:
            self.cells.append(" ".join("".join(self.cell_parts).split()))
            self.in_cell = False
            self.cell_parts = []
        elif tag == "tr" and self.in_row:
            self.in_row = False
            if len(self.cells) < 6 or not re.fullmatch(r"\d{2}/\d{2}/\d{4}", self.cells[0]):
                return
            try:
                day = datetime.strptime(self.cells[0], "%d/%m/%Y").date()
            except ValueError:
                return
            self.rows.append({
                "date": day.isoformat(),
                "close": self.cells[1],
                "volume": self.cells[2],
                "open": self.cells[3],
                "high": self.cells[4],
                "low": self.cells[5],
            })


def parse_page(body: bytes) -> list[dict[str, str]]:
    parser = HistoryParser()
    parser.feed(body.decode("utf-8", "replace"))
    return parser.rows


def fetch_page(symbol: str, page: int, page_cache: dict[int, tuple[list[dict[str, str]], dict[str, str]]]
               ) -> tuple[list[dict[str, str]], dict[str, str]]:
    if page in page_cache:
        return page_cache[page]

    path = RAW / f"{symbol.upper()}-page-{page}.html"
    url = BASE + "?" + urlencode({"cP": page, "id": symbol.lower()})
    body = path.read_bytes() if path.exists() and path.stat().st_size else b""
    status = "CACHE" if body else "ERROR"
    error = ""
    if not body:
        for attempt in range(4):
            try:
                request = Request(url, headers={
                    "User-Agent": USER_AGENT,
                    "Accept": "text/html,application/xhtml+xml",
                })
                with urlopen(request, timeout=30) as response:
                    body = response.read()
                    status = str(response.status)
                path.write_bytes(body)
                break
            except HTTPError as exc:
                error = f"HTTPError: {exc.code} {exc.reason}"
                if exc.code not in (408, 425, 429, 500, 502, 503, 504) or attempt == 3:
                    break
                time.sleep(0.5 * (attempt + 1))
            except (URLError, TimeoutError, OSError) as exc:
                error = f"{type(exc).__name__}: {exc}"
                if attempt < 3:
                    time.sleep(0.5 * (attempt + 1))

    if not body and path.exists() and path.stat().st_size:
        body = path.read_bytes()
        status = "CACHE"
        error = ""
    digest = hashlib.sha256(body).hexdigest() if body else ""
    rows = parse_page(body) if body else []
    dates = [row["date"] for row in rows]
    meta = {
        "symbol": symbol.upper(),
        "page": str(page),
        "http_status": status if body else "ERROR",
        "request_url": url,
        "raw_file": path.name if body else "",
        "response_sha256": digest,
        "response_bytes": str(len(body)) if body else "",
        "row_count": str(len(rows)),
        "newest_date": max(dates) if dates else "",
        "oldest_date": min(dates) if dates else "",
        "error": error,
    }
    result = (rows, meta)
    page_cache[page] = result
    return result


def find_bar(symbol: str, target: date, page_cache: dict[int, tuple[list[dict[str, str]], dict[str, str]]]
             ) -> tuple[dict[str, str] | None, str]:
    rows, meta = fetch_page(symbol, 1, page_cache)
    if meta["http_status"] == "ERROR":
        return None, "fetch_error"
    by_date = {row["date"]: row for row in rows}
    if target.isoformat() in by_date:
        return by_date[target.isoformat()], "matched"
    if not rows:
        return None, "empty_history"

    newest = date.fromisoformat(meta["newest_date"])
    oldest = date.fromisoformat(meta["oldest_date"])
    if target > newest:
        return None, "newer_than_source_history"
    if target >= oldest:
        return None, "date_missing_on_page"

    lower = 1  # lower page bound is newer than the target
    upper = 2
    upper_rows: list[dict[str, str]] = []
    upper_meta: dict[str, str] = {}
    while upper <= MAX_PAGE:
        upper_rows, upper_meta = fetch_page(symbol, upper, page_cache)
        if upper_meta["http_status"] == "ERROR":
            return None, "fetch_error"
        if not upper_rows:
            break
        upper_by_date = {row["date"]: row for row in upper_rows}
        if target.isoformat() in upper_by_date:
            return upper_by_date[target.isoformat()], "matched"
        page_newest = date.fromisoformat(upper_meta["newest_date"])
        page_oldest = date.fromisoformat(upper_meta["oldest_date"])
        if target >= page_oldest:
            break
        lower = upper
        upper *= 2
    else:
        return None, "page_search_limit"

    lo = lower + 1
    hi = upper - 1
    while lo <= hi:
        page = (lo + hi) // 2
        page_rows, page_meta = fetch_page(symbol, page, page_cache)
        if page_meta["http_status"] == "ERROR":
            return None, "fetch_error"
        if not page_rows:
            hi = page - 1
            continue
        page_by_date = {row["date"]: row for row in page_rows}
        if target.isoformat() in page_by_date:
            return page_by_date[target.isoformat()], "matched"
        page_newest = date.fromisoformat(page_meta["newest_date"])
        page_oldest = date.fromisoformat(page_meta["oldest_date"])
        if target > page_newest:
            hi = page - 1
        elif target < page_oldest:
            lo = page + 1
        else:
            return None, "date_missing_between_page_rows"
    return None, "date_missing_from_source"


def process_symbol(symbol: str, candidates: list[dict[str, str]]) -> tuple[list[dict[str, str]], list[dict[str, str]]]:
    page_cache: dict[int, tuple[list[dict[str, str]], dict[str, str]]] = {}
    output: list[dict[str, str]] = []
    for candidate in sorted(candidates, key=lambda row: row["trade_date"]):
        target = date.fromisoformat(candidate["trade_date"])
        bar, status = find_bar(symbol, target, page_cache)
        result = {key: candidate[key] for key in candidate}
        result.update({
            "cross_source": "cophieu68",
            "cross_source_status": status,
            "cross_open": bar["open"] if bar else "",
            "cross_high": bar["high"] if bar else "",
            "cross_low": bar["low"] if bar else "",
            "cross_close": bar["close"] if bar else "",
            "cross_volume": bar["volume"] if bar else "",
        })
        if bar:
            matched_page = next((page for page, (rows, _meta) in page_cache.items()
                                 if any(row["date"] == bar["date"] for row in rows)), None)
            if matched_page is not None:
                _rows, page_meta = page_cache[matched_page]
                result["cross_source_url"] = page_meta["request_url"]
                result["cross_source_sha256"] = page_meta["response_sha256"]
                result["cross_source_raw_file"] = page_meta["raw_file"]
                result["cross_source_page"] = str(matched_page)
            else:
                result["cross_source_url"] = ""
                result["cross_source_sha256"] = ""
                result["cross_source_raw_file"] = ""
                result["cross_source_page"] = ""
        else:
            result["cross_source_url"] = ""
            result["cross_source_sha256"] = ""
            result["cross_source_raw_file"] = ""
            result["cross_source_page"] = ""
        output.append(result)
    return output, [meta for _rows, meta in page_cache.values()]


def write_csv(path: Path, fields: list[str], rows: list[dict[str, str]]) -> None:
    with path.open("w", encoding="utf-8-sig", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=fields, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)


def main() -> int:
    RAW.mkdir(parents=True, exist_ok=True)
    with INPUT.open(encoding="utf-8-sig", newline="") as stream:
        input_rows = list(csv.DictReader(stream))
    groups: dict[str, list[dict[str, str]]] = {}
    for row in input_rows:
        groups.setdefault(row["symbol"].upper(), []).append(row)

    results: list[dict[str, str]] = []
    fetches: dict[tuple[str, str], dict[str, str]] = {}
    errors: list[str] = []
    with ThreadPoolExecutor(max_workers=MAX_WORKERS) as pool:
        futures = {pool.submit(process_symbol, symbol, rows): symbol for symbol, rows in groups.items()}
        for future in as_completed(futures):
            symbol = futures[future]
            try:
                symbol_rows, symbol_fetches = future.result()
                results.extend(symbol_rows)
                for meta in symbol_fetches:
                    fetches[(meta["symbol"], meta["page"])] = meta
            except Exception as exc:  # preserve per-symbol failures while completing the rest
                errors.append(f"{symbol}: {type(exc).__name__}: {exc}")

    results.sort(key=lambda row: (row["trade_date"], row["symbol"]))
    fetch_rows = sorted(fetches.values(), key=lambda row: (row["symbol"], int(row["page"])))
    extra = ["cross_source", "cross_source_status", "cross_open", "cross_high", "cross_low",
             "cross_close", "cross_volume", "cross_source_url", "cross_source_sha256",
             "cross_source_raw_file", "cross_source_page"]
    fields = list(input_rows[0]) + extra if input_rows else extra
    write_csv(OUTPUT, fields, results)
    write_csv(FETCHES, ["symbol", "page", "http_status", "request_url", "raw_file",
                        "response_sha256", "response_bytes", "row_count", "newest_date",
                        "oldest_date", "error"], fetch_rows)

    matched = [row for row in results if row["cross_source_status"] == "matched"]
    close_volume_agree = sum(row["cross_close"] == row["c"] and row["cross_volume"].replace(",", "") == row["v"]
                             for row in matched)
    print(f"candidates={len(input_rows)} symbols={len(groups)} matched={len(matched)} "
          f"close_and_volume_exact={close_volume_agree} pages_archived={len(fetch_rows)} "
          f"page_errors={sum(row['http_status'] == 'ERROR' for row in fetch_rows)} symbol_errors={len(errors)}")
    for error in errors:
        print(error)
    print(f"wrote {OUTPUT} and {FETCHES}; archived pages in {RAW}")
    return 0 if not errors else 1


if __name__ == "__main__":
    raise SystemExit(main())
