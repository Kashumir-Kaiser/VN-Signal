#!/usr/bin/env python3
"""Archive secondary event-price calculations for the 42 confirmed actions."""

from __future__ import annotations

import csv
import hashlib
import re
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime
from html.parser import HTMLParser
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


ROOT = Path(__file__).resolve().parent
RAW = ROOT / "cophieu68-action-calculations"
OUTPUT = ROOT / "cophieu68-action-calculation-index.csv"
INPUT = ROOT / "reference-snapshot-audit.csv"
NOTICES = ROOT / "vsdc-event-notice-index.csv"
BASE = "https://cophieu68.vn/quote/event_calc.php?id={}"
USER_AGENT = "Mozilla/5.0 (compatible; VN-Signal historical adjustment audit)"


class Rows(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.rows: list[list[str]] = []
        self.row: list[str] | None = None
        self.cell: list[str] | None = None

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if tag == "tr":
            self.row = []
        elif tag in {"td", "th"} and self.row is not None:
            self.cell = []
        elif tag == "br" and self.cell is not None:
            self.cell.append(" ")

    def handle_data(self, data: str) -> None:
        if self.cell is not None:
            self.cell.append(data)

    def handle_endtag(self, tag: str) -> None:
        if tag in {"td", "th"} and self.cell is not None and self.row is not None:
            self.row.append(" ".join("".join(self.cell).split()))
            self.cell = None
        elif tag == "tr" and self.row is not None:
            if self.row:
                self.rows.append(self.row)
            self.row = None
            self.cell = None


def get_page(ticker: str) -> tuple[str, str, str, bytes]:
    url = BASE.format(ticker.lower())
    path = RAW / f"{ticker.upper()}.html"
    if path.exists() and path.stat().st_size:
        body = path.read_bytes()
        return ticker, url, "CACHE", body
    error = ""
    for attempt in range(3):
        try:
            time.sleep(0.1)
            request = Request(url, headers={"User-Agent": USER_AGENT, "Accept": "text/html"})
            with urlopen(request, timeout=20) as response:
                body = response.read()
                status = str(response.status)
            path.write_bytes(body)
            return ticker, url, status, body
        except (HTTPError, URLError, TimeoutError, OSError) as exc:
            error = f"{type(exc).__name__}: {exc}"
            if attempt < 2:
                time.sleep(0.5 * (attempt + 1))
    return ticker, url, "ERROR:" + error, b""


def extract(ticker: str, candidate_date: str, html: str) -> dict[str, str]:
    parser = Rows()
    parser.feed(html)
    expected = datetime.strptime(candidate_date, "%Y-%m-%d").date()
    matches: list[list[str]] = []
    for row in parser.rows:
        if not row:
            continue
        m = re.search(r"\b(\d{2}/\d{2}/\d{4})\b", row[0])
        if m and datetime.strptime(m.group(1), "%d/%m/%Y").date() == expected:
            matches.append(row)
    if not matches:
        return {"ticker": ticker, "candidate_date": candidate_date, "match_status": "NO_EXACT_CALC_ROW",
                "description": "", "published_reference": "", "previous_close": "",
                "cophieu_event_factor": ""}

    row = matches[0]
    description = row[1] if len(row) > 1 else ""
    calculation = row[3] if len(row) > 3 else ""
    # The fourth event-calculation column explicitly labels the ex-right
    # reference as (O) and the prior close as (LC).
    ref_match = re.search(r"([0-9]+(?:\.[0-9]+)?)\s*\(O\)", calculation)
    close_match = re.search(r"\(([0-9]+(?:\.[0-9]+)?)\)\s*\(LC\)", calculation)
    reference = float(ref_match.group(1)) if ref_match else None
    previous = float(close_match.group(1)) if close_match else None
    factor = reference / previous if reference is not None and previous else None
    return {"ticker": ticker, "candidate_date": candidate_date,
            "match_status": "EXACT_CALC_ROW" if factor is not None else "PARSE_INCOMPLETE",
            "description": description,
            "published_reference": f"{reference:.12g}" if reference is not None else "",
            "previous_close": f"{previous:.12g}" if previous is not None else "",
            "cophieu_event_factor": f"{factor:.12g}" if factor is not None else ""}


def main() -> int:
    RAW.mkdir(parents=True, exist_ok=True)
    with INPUT.open(encoding="utf-8-sig", newline="") as stream:
        audit = {(row["ticker"].upper(), row["trade_date"]): row for row in csv.DictReader(stream)}
    with NOTICES.open(encoding="utf-8-sig", newline="") as stream:
        notice_rows = list(csv.DictReader(stream))
    keys = {(row["ticker"].upper(), row["candidate_date"]) for row in notice_rows}
    keys.add(("AAM", "2019-07-10"))
    missing = keys - audit.keys()
    if missing:
        raise RuntimeError(f"action keys absent from candidate audit: {sorted(missing)}")
    tickers = sorted({ticker for ticker, _ in keys})
    pages: dict[str, tuple[str, str, bytes]] = {}
    with ThreadPoolExecutor(max_workers=5) as pool:
        futures = {pool.submit(get_page, ticker): ticker for ticker in tickers}
        for future in as_completed(futures):
            ticker, url, status, body = future.result()
            pages[ticker] = (url, status, body)
    output: list[dict[str, str]] = []
    for ticker, candidate_date in sorted(keys, key=lambda key: (key[1], key[0])):
        url, status, body = pages[ticker]
        detail = extract(ticker, candidate_date, body.decode("utf-8", "replace")) if body else {
            "ticker": ticker, "candidate_date": candidate_date, "match_status": "FETCH_ERROR",
            "description": "", "published_reference": "", "previous_close": "", "cophieu_event_factor": ""}
        output.append({
            **detail,
            "exchange_code": audit[(ticker, candidate_date)]["exchange_code"],
            "vndirect_reference_baseline": audit[(ticker, candidate_date)]["reference_baseline"],
            "vndirect_basic_price": audit[(ticker, candidate_date)]["basic_price"],
            "event_calc_url": url,
            "http_status": status,
            "response_sha256": hashlib.sha256(body).hexdigest() if body else "",
            "raw_file": f"{ticker}.html" if body else "",
        })
    fields = ["ticker", "candidate_date", "exchange_code", "match_status", "description",
              "published_reference", "previous_close", "cophieu_event_factor",
              "vndirect_reference_baseline", "vndirect_basic_price", "event_calc_url",
              "http_status", "response_sha256", "raw_file"]
    with OUTPUT.open("w", encoding="utf-8-sig", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=fields)
        writer.writeheader()
        writer.writerows(output)
    failures = sum(row["match_status"] not in {"EXACT_CALC_ROW"} for row in output)
    print(f"actions={len(keys)} exact_calculations={len(keys)-failures} fetch_or_parse_gaps={failures}")
    print(f"wrote {OUTPUT}; archived calculations in {RAW}")
    return 1 if any(row["http_status"].startswith("ERROR:") for row in output) else 0


if __name__ == "__main__":
    raise SystemExit(main())
