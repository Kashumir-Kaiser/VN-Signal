#!/usr/bin/env python3
"""Fetch public Cophieu68 action calendars for factor-disagreement candidates.

This is an evidence-indexing aid only. Cophieu68 is secondary evidence; any
manual adjustment decision must cite an exchange, VSDC, or issuer source.
"""

from __future__ import annotations

import csv
import hashlib
import re
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timedelta
from html.parser import HTMLParser
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


ROOT = Path(__file__).resolve().parent
INPUT = ROOT / "reference-snapshot-audit.csv"
RAW = ROOT / "cophieu68-event-pages"
FETCHES = ROOT / "cophieu68-event-fetches.csv"
EVENTS = ROOT / "cophieu68-event-calendar.csv"
MATCHES = ROOT / "cophieu68-candidate-event-matches.csv"
BASE = "https://cophieu68.vn/quote/event.php?id={}"
DATE_RE = re.compile(r"\b(\d{2})/(\d{2})/(\d{4})\b")


class TableRows(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.rows: list[list[str]] = []
        self._row: list[str] | None = None
        self._cell: list[str] | None = None

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if tag == "tr":
            self._row = []
        elif tag in ("td", "th") and self._row is not None:
            self._cell = []
        elif tag == "br" and self._cell is not None:
            self._cell.append(" ")

    def handle_endtag(self, tag: str) -> None:
        if tag in ("td", "th") and self._cell is not None and self._row is not None:
            self._row.append(" ".join("".join(self._cell).split()))
            self._cell = None
        elif tag == "tr" and self._row is not None:
            if self._row:
                self.rows.append(self._row)
            self._row = None
            self._cell = None

    def handle_data(self, data: str) -> None:
        if self._cell is not None:
            self._cell.append(data)


def get_page(ticker: str) -> tuple[str, str, str, str]:
    url = BASE.format(ticker.lower())
    path = RAW / f"{ticker.upper()}.html"
    if path.exists() and path.stat().st_size:
        body = path.read_bytes()
        return ticker, url, "CACHE", body.decode("utf-8", "replace")
    for attempt in range(3):
        try:
            time.sleep(0.12)
            req = Request(url, headers={"User-Agent": "Mozilla/5.0 (compatible; VN-Signal research audit)"})
            with urlopen(req, timeout=25) as response:
                body = response.read()
            path.write_bytes(body)
            return ticker, url, "200", body.decode("utf-8", "replace")
        except (HTTPError, URLError, TimeoutError, OSError) as exc:
            if attempt == 2:
                return ticker, url, f"ERROR:{type(exc).__name__}:{exc}", ""
            time.sleep(0.5 * (attempt + 1))
    raise AssertionError("retry loop fell through")


def main() -> int:
    RAW.mkdir(parents=True, exist_ok=True)
    with INPUT.open(encoding="utf-8-sig", newline="") as f:
        candidates = list(csv.DictReader(f))
    tickers = sorted({r["ticker"].upper() for r in candidates})
    pages: dict[str, tuple[str, str, str]] = {}
    with ThreadPoolExecutor(max_workers=8) as pool:
        futures = [pool.submit(get_page, ticker) for ticker in tickers]
        for future in as_completed(futures):
            ticker, url, status, html = future.result()
            pages[ticker] = (url, status, html)

    fetch_rows: list[dict[str, str]] = []
    event_rows: list[dict[str, str]] = []
    for ticker in tickers:
        url, status, html = pages[ticker]
        digest = hashlib.sha256(html.encode("utf-8")).hexdigest() if html else ""
        fetch_rows.append({"ticker": ticker, "url": url, "status": status,
                           "sha256": digest, "bytes": str(len(html.encode("utf-8")))})
        if not html:
            continue
        parser = TableRows()
        parser.feed(html)
        current: dict[str, str] | None = None
        for cells in parser.rows:
            joined = " | ".join(cells)
            dates = [f"{y}-{m}-{d}" for d, m, y in DATE_RE.findall(joined)]
            if len(cells) >= 3 and dates and len(cells[0]) < 180:
                if current:
                    event_rows.append(current)
                current = {"ticker": ticker, "event_dates": ";".join(dates),
                           "event": cells[0], "ratio": cells[2] if len(cells) > 2 else "",
                           "details": " | ".join(cells[3:]), "url": url}
            elif current and joined:
                current["details"] = (current["details"] + " | " + joined).strip(" |")
        if current:
            event_rows.append(current)

    with FETCHES.open("w", encoding="utf-8-sig", newline="") as f:
        w = csv.DictWriter(f, fieldnames=["ticker", "url", "status", "sha256", "bytes"])
        w.writeheader(); w.writerows(fetch_rows)
    event_fields = ["ticker", "event_dates", "event", "ratio", "details", "url"]
    with EVENTS.open("w", encoding="utf-8-sig", newline="") as f:
        w = csv.DictWriter(f, fieldnames=event_fields)
        w.writeheader(); w.writerows(event_rows)

    matches: list[dict[str, str]] = []
    by_ticker: dict[str, list[dict[str, str]]] = {}
    for event in event_rows:
        by_ticker.setdefault(event["ticker"], []).append(event)
    for row in candidates:
        try:
            target = datetime.strptime(row["trade_date"], "%Y-%m-%d").date()
        except ValueError:
            continue
        for event in by_ticker.get(row["ticker"].upper(), []):
            parsed_dates = []
            for value in event["event_dates"].split(";"):
                try:
                    parsed_dates.append(datetime.strptime(value, "%Y-%m-%d").date())
                except ValueError:
                    pass
            if parsed_dates and min(abs((d - target).days) for d in parsed_dates) <= 4:
                matches.append({"candidate_ticker": row["ticker"],
                                "candidate_date": row["trade_date"],
                                "exchange": row["exchange_code"],
                                "model_factor": row["model_factor"],
                                "snapshot_event_factor": row["snapshot_event_factor"],
                                "no_trade_rows_before": row["no_trade_rows_before"],
                                "last_traded_date": row["last_traded_date"],
                                **event})
    match_fields = ["candidate_ticker", "candidate_date", "exchange", "model_factor",
                    "snapshot_event_factor", "no_trade_rows_before", "last_traded_date",
                    *event_fields]
    with MATCHES.open("w", encoding="utf-8-sig", newline="") as f:
        w = csv.DictWriter(f, fieldnames=match_fields)
        w.writeheader(); w.writerows(matches)
    print(f"tickers={len(tickers)} fetched={sum(p[1] not in ('ERROR',) and not p[1].startswith('ERROR:') for p in pages.values())}")
    print(f"fetch errors={sum(p[1].startswith('ERROR:') for p in pages.values())} events={len(event_rows)} matches={len(matches)}")
    print(f"wrote {FETCHES} {EVENTS} {MATCHES}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
