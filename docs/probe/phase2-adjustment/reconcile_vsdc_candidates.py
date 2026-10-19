#!/usr/bin/env python3
"""Index official VSDC rights-calendar records for Phase 2 factor conflicts.

The crawler sends read-only public searches to VSDC. It does not change any
market-data row. It archives every response and records a SHA-256 so candidate
events can be checked against the source notice before an override is written.
"""

from __future__ import annotations

import csv
import hashlib
import json
import re
import threading
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import date, timedelta
from html.parser import HTMLParser
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import HTTPCookieProcessor, Request, build_opener
import http.cookiejar


ROOT = Path(__file__).resolve().parent
INPUT = ROOT / "reference-snapshot-audit.csv"
RAW = ROOT / "vsdc-calendar-pages"
OUTPUT = ROOT / "vsdc-candidate-calendar.csv"
FETCHES = ROOT / "vsdc-candidate-fetches.csv"
BASE = "https://vsdc.vn"
USER_AGENT = "Mozilla/5.0 (compatible; VN-Signal research audit)"
PAGE_SIZE = 1000
LOOKAHEAD_DAYS = 90
_local = threading.local()


class TableParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.rows: list[list[dict[str, str]]] = []
        self.row: list[dict[str, str]] | None = None
        self.cell: dict[str, str] | None = None
        self._data: list[str] = []
        self._anchor: str | None = None
        self._anchor_data: list[str] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        attrs_map = dict(attrs)
        if tag == "tr":
            self.row = []
        elif tag in ("td", "th") and self.row is not None:
            self.cell = {"text": "", "href": ""}
            self._data = []
        elif tag == "a" and self.cell is not None:
            self._anchor = attrs_map.get("href", "") or ""
            self._anchor_data = []

    def handle_data(self, data: str) -> None:
        if self.cell is not None:
            self._data.append(data)
        if self._anchor is not None:
            self._anchor_data.append(data)

    def handle_endtag(self, tag: str) -> None:
        if tag == "a" and self._anchor is not None and self.cell is not None:
            self.cell["href"] = self._anchor
            self.cell["link_text"] = " ".join("".join(self._anchor_data).split())
            self._anchor = None
            self._anchor_data = []
        elif tag in ("td", "th") and self.cell is not None and self.row is not None:
            self.cell["text"] = " ".join("".join(self._data).split())
            self.row.append(self.cell)
            self.cell = None
            self._data = []
        elif tag == "tr" and self.row is not None:
            if self.row:
                self.rows.append(self.row)
            self.row = None


def _session() -> tuple[object, str]:
    opener = getattr(_local, "opener", None)
    token = getattr(_local, "token", None)
    if opener is None or token is None:
        jar = http.cookiejar.CookieJar()
        opener = build_opener(HTTPCookieProcessor(jar))
        page_url = BASE + "/vi/lich-giao-dich?" + urlencode({"date": "01/01/2021", "tab": "LICH_THQ"})
        req = Request(page_url, headers={"User-Agent": USER_AGENT, "Accept": "text/html"})
        with opener.open(req, timeout=30) as response:
            html = response.read().decode("utf-8", "replace")
        match = re.search(r'<meta name="__VPToken" content="([^"]+)', html)
        if not match:
            raise RuntimeError("VSDC calendar page did not contain its request token")
        token = match.group(1)
        _local.opener = opener
        _local.token = token
    return opener, token


def _parse_table(body: str) -> list[dict[str, str]]:
    parser = TableParser()
    parser.feed(body)
    output: list[dict[str, str]] = []
    for row in parser.rows:
        cells = [cell.get("text", "") for cell in row]
        if len(cells) < 8 or cells[0].strip().lower() in {"stt", "no."}:
            continue
        title = cells[4]
        href = next((cell.get("href", "") for cell in row if cell.get("href")), "")
        output.append({
            "record_date": cells[1],
            "ticker": cells[2].upper(),
            "isin": cells[3],
            "title": title,
            "instrument_type": cells[5],
            "exchange": cells[6],
            "notice_url": BASE + href if href.startswith("/") else href,
        })
    return output


def _fetch_one(candidate: dict[str, str]) -> tuple[dict[str, str], list[dict[str, str]]]:
    ticker = candidate["ticker"].strip().upper()
    first = date.fromisoformat(candidate["trade_date"])
    start = first.strftime("%d/%m/%Y")
    end = (first + timedelta(days=LOOKAHEAD_DAYS)).strftime("%d/%m/%Y")
    search_key = f"{ticker}|||{start}|{end}|VI"
    payload = json.dumps({
        "SearchKey": search_key,
        "CurrentPage": 1,
        "RecordOnPage": PAGE_SIZE,
        "OrderBy": "",
        "OrderType": "",
    }).encode("utf-8")
    query_url = BASE + "/lich-thq/search"
    for attempt in range(3):
        try:
            opener, token = _session()
            req = Request(query_url, data=payload, headers={
                "User-Agent": USER_AGENT,
                "Accept": "*/*",
                "Content-Type": "application/json;charset=utf-8",
                "Origin": BASE,
                "Referer": BASE + "/vi/lich-giao-dich?tab=LICH_THQ",
                "X-Requested-With": "XMLHttpRequest",
                "__VPToken": token,
            }, method="POST")
            with opener.open(req, timeout=30) as response:
                body = response.read()
            raw_path = RAW / f"{ticker}-{first.isoformat()}.html"
            raw_path.write_bytes(body)
            digest = hashlib.sha256(body).hexdigest()
            records = _parse_table(body.decode("utf-8", "replace"))
            fetch = {
                "ticker": ticker,
                "candidate_date": first.isoformat(),
                "query_start": start,
                "query_end": end,
                "status": "200",
                "response_sha256": digest,
                "response_bytes": str(len(body)),
                "raw_file": raw_path.name,
                "record_count": str(len(records)),
                "error": "",
            }
            return fetch, records
        except (HTTPError, URLError, TimeoutError, OSError, RuntimeError) as exc:
            if attempt < 2:
                time.sleep(0.5 * (attempt + 1))
                continue
            fetch = {
                "ticker": ticker,
                "candidate_date": first.isoformat(),
                "query_start": start,
                "query_end": end,
                "status": "ERROR",
                "response_sha256": "",
                "response_bytes": "",
                "raw_file": "",
                "record_count": "",
                "error": f"{type(exc).__name__}: {exc}",
            }
            return fetch, []
    raise AssertionError("retry loop fell through")


def _write(path: Path, fields: list[str], rows: list[dict[str, str]]) -> None:
    with path.open("w", encoding="utf-8-sig", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)


def main() -> int:
    RAW.mkdir(parents=True, exist_ok=True)
    with INPUT.open(encoding="utf-8-sig", newline="") as stream:
        candidates = list(csv.DictReader(stream))
    # One VSDC query per distinct ticker/date pair; duplicate entries, if any,
    # are retained in the audit output but do not repeat the public request.
    unique = {(row["ticker"].upper(), row["trade_date"]): row for row in candidates}
    results: dict[tuple[str, str], tuple[dict[str, str], list[dict[str, str]]]] = {}
    with ThreadPoolExecutor(max_workers=6) as pool:
        futures = {pool.submit(_fetch_one, row): key for key, row in unique.items()}
        for future in as_completed(futures):
            results[futures[future]] = future.result()

    output_rows: list[dict[str, str]] = []
    fetch_rows: list[dict[str, str]] = []
    for key, candidate in sorted(unique.items(), key=lambda item: (item[0][1], item[0][0])):
        fetch, records = results[key]
        fetch_rows.append(fetch)
        for record in records:
            output_rows.append({
                "candidate_ticker": candidate["ticker"],
                "candidate_date": candidate["trade_date"],
                "exchange_code": candidate["exchange_code"],
                "model_factor": candidate["model_factor"],
                "snapshot_event_factor": candidate["snapshot_event_factor"],
                **record,
                "response_sha256": fetch["response_sha256"],
                "raw_file": fetch["raw_file"],
            })
    _write(FETCHES, [
        "ticker", "candidate_date", "query_start", "query_end", "status",
        "response_sha256", "response_bytes", "raw_file", "record_count", "error",
    ], fetch_rows)
    _write(OUTPUT, [
        "candidate_ticker", "candidate_date", "exchange_code", "model_factor",
        "snapshot_event_factor", "record_date", "ticker", "isin", "title",
        "instrument_type", "exchange", "notice_url", "response_sha256", "raw_file",
    ], output_rows)
    errors = sum(row["status"] != "200" for row in fetch_rows)
    print(f"candidates={len(candidates)} unique_queries={len(unique)} errors={errors} official_records={len(output_rows)}")
    print(f"wrote {OUTPUT} and {FETCHES}; response pages in {RAW}")
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
