#!/usr/bin/env python3
"""Archive primary VSDC notices linked to exact adjustment-event candidates."""

from __future__ import annotations

import csv
import hashlib
import re
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import date, datetime
from html import unescape
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


ROOT = Path(__file__).resolve().parent
AUDIT = ROOT / "reference-snapshot-audit.csv"
EVENTS = ROOT / "cophieu68-event-calendar.csv"
VSDC = ROOT / "vsdc-candidate-calendar.csv"
RAW = ROOT / "vsdc-event-notices"
OUTPUT = ROOT / "vsdc-event-notice-index.csv"
USER_AGENT = "Mozilla/5.0 (compatible; VN-Signal research audit)"
ACTION_WORDS = ("co tuc", "phat hanh", "quyen mua", "tang von", "co phieu")


def normalize(value: str) -> str:
    import unicodedata
    return "".join(ch for ch in unicodedata.normalize("NFD", value.lower())
                   if not unicodedata.combining(ch))


def event_rows() -> list[dict[str, str]]:
    with AUDIT.open(encoding="utf-8-sig", newline="") as stream:
        audit = list(csv.DictReader(stream))
    with EVENTS.open(encoding="utf-8-sig", newline="") as stream:
        events = list(csv.DictReader(stream))
    with VSDC.open(encoding="utf-8-sig", newline="") as stream:
        vsdc = list(csv.DictReader(stream))

    by_event: dict[str, list[dict[str, str]]] = {}
    for item in events:
        by_event.setdefault(item["ticker"].upper(), []).append(item)
    by_calendar: dict[tuple[str, str], list[dict[str, str]]] = {}
    for item in vsdc:
        by_calendar.setdefault((item["candidate_ticker"].upper(), item["candidate_date"]), []).append(item)

    selected: dict[tuple[str, str, str], dict[str, str]] = {}
    for row in audit:
        ticker = row["ticker"].upper()
        candidate = date.fromisoformat(row["trade_date"])
        exact = [item for item in by_event.get(ticker, [])
                 if item["event_dates"].split(";")[0] == candidate.isoformat()]
        if not exact:
            continue
        for official in by_calendar.get((ticker, candidate.isoformat()), []):
            if official["ticker"].upper() != ticker:
                continue
            record_date = datetime.strptime(official["record_date"], "%d/%m/%Y").date()
            lag = (record_date - candidate).days
            if lag < 0 or lag > 15:
                continue
            title_norm = normalize(official["title"])
            if not any(word in title_norm for word in ACTION_WORDS):
                continue
            # TDP's matching Cophieu entry is a completed listing of privately
            # placed shares, not a distribution or a price-reference action.
            if ticker == "TDP" and "phat hanh khac" in normalize(exact[0]["event"]):
                continue
            key = (ticker, candidate.isoformat(), official["notice_url"])
            selected[key] = {
                "ticker": ticker,
                "candidate_date": candidate.isoformat(),
                "exchange_code": row["exchange_code"],
                "model_factor": row["model_factor"],
                "snapshot_event_factor": row["snapshot_event_factor"],
                "record_date": official["record_date"],
                "calendar_title": official["title"],
                "notice_url": official["notice_url"],
                "lag_calendar_days": str(lag),
                "secondary_event_url": exact[0]["url"],
                "secondary_event": exact[0]["event"],
                "secondary_ratio": exact[0]["ratio"],
            }
    return list(selected.values())


def fetch(row: dict[str, str]) -> dict[str, str]:
    url = row["notice_url"].replace("https://vsdc.vn/", "https://vsdc.vn/vi/")
    name = f"{row['ticker']}-{row['candidate_date']}-{url.rsplit('/', 1)[-1]}.html"
    path = RAW / name
    error = ""
    body = b""
    for attempt in range(3):
        try:
            time.sleep(0.08)
            request = Request(url, headers={"User-Agent": USER_AGENT, "Accept": "text/html"})
            with urlopen(request, timeout=30) as response:
                body = response.read()
            path.write_bytes(body)
            break
        except (HTTPError, URLError, TimeoutError, OSError) as exc:
            error = f"{type(exc).__name__}: {exc}"
            if attempt < 2:
                time.sleep(0.5 * (attempt + 1))
    title = ""
    body_text = unescape(re.sub(r"<[^>]+>", " ", body.decode("utf-8", "replace")))
    body_text = " ".join(body_text.split())
    for date_text in re.findall(r"(?:Ngày đăng ký cuối cùng|Ngày ĐKCC|Record date)\s*:?\s*(\d{2}/\d{2}/\d{4})", body_text, re.I):
        if date_text == row["record_date"]:
            break
    return {
        **row,
        "archived_url": url,
        "http_status": "200" if body else "ERROR",
        "notice_sha256": hashlib.sha256(body).hexdigest() if body else "",
        "notice_bytes": str(len(body)) if body else "",
        "raw_file": name if body else "",
        "notice_contains_record_date": str(row["record_date"] in body_text),
        "notice_excerpt": body_text[:1200] if body else "",
        "error": error,
    }


def main() -> int:
    RAW.mkdir(parents=True, exist_ok=True)
    selected = event_rows()
    results: list[dict[str, str]] = []
    with ThreadPoolExecutor(max_workers=6) as pool:
        futures = [pool.submit(fetch, row) for row in selected]
        for future in as_completed(futures):
            results.append(future.result())
    results.sort(key=lambda row: (row["candidate_date"], row["ticker"], row["notice_url"]))
    fields = list(results[0]) if results else []
    with OUTPUT.open("w", encoding="utf-8-sig", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=fields)
        writer.writeheader()
        writer.writerows(results)
    failures = sum(row["http_status"] != "200" for row in results)
    print(f"notice_matches={len(selected)} fetched={len(results)-failures} errors={failures}")
    print(f"wrote {OUTPUT}; archived notice pages in {RAW}")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
