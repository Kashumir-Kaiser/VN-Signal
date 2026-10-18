"""Archive Simplize's public history responses and reconcile reported volume.

This is a bounded research check for the project's 16 UPCoM partial-history
symbols. It does not import data into PostgreSQL or modify canonical bars.
"""

from __future__ import annotations

import csv
import hashlib
import json
import time
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


ROOT = Path(__file__).resolve().parent
RAW = ROOT / "raw"
ISSUE_CSV = Path(__file__).resolve().parents[1] / "phase1-cafef-history-audit" / "issue-coverage-cafef.csv"
SYMBOLS = (
    "CDG", "GGG", "HPI", "NAS", "SBD", "SDD", "SHC", "SNC",
    "SPC", "SVG", "TNB", "VFC", "VNI", "VNX", "XMC", "XPH",
)
PAGE_SIZE = 1000
BASE_URL = "https://api.simplize.vn/api/historical/quote/prices"


def fetch(symbol: str, page: int) -> tuple[str, bytes, dict]:
    url = f"{BASE_URL}/{symbol}?page={page}&size={PAGE_SIZE}"
    request = Request(
        url,
        headers={
            "Accept": "application/json, text/plain, */*",
            "Origin": "https://simplize.vn",
            "Referer": "https://simplize.vn/",
            "User-Agent": (
                "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
                "AppleWebKit/537.36 (KHTML, like Gecko) "
                "Chrome/140.0.0.0 Safari/537.36"
            ),
        },
    )
    try:
        with urlopen(request, timeout=60) as response:
            raw = response.read()
            payload = json.loads(raw)
            if response.status != 200 or payload.get("status") != 200:
                raise RuntimeError(f"{symbol} page {page}: HTTP/API status not successful")
            return url, raw, payload
    except (HTTPError, URLError) as exc:
        raise RuntimeError(f"{symbol} page {page}: {exc}") from exc


def date_of(row: dict) -> str:
    return datetime.fromtimestamp(int(row["date"]), timezone.utc).date().isoformat()


def main() -> None:
    RAW.mkdir(parents=True, exist_ok=True)
    manifest: list[dict] = []
    history: dict[tuple[str, str], dict] = {}

    for symbol in SYMBOLS:
        first_url, first_raw, first_payload = fetch(symbol, 0)
        total = int(first_payload.get("total", 0))
        page_count = max(1, (total + PAGE_SIZE - 1) // PAGE_SIZE)
        for page in range(page_count):
            if page == 0:
                url, raw, payload = first_url, first_raw, first_payload
            else:
                time.sleep(0.2)
                url, raw, payload = fetch(symbol, page)
            rows = payload.get("data") or []
            path = RAW / f"{symbol}-page-{page:02d}.json"
            path.write_bytes(raw)
            dates = [date_of(row) for row in rows]
            manifest.append({
                "symbol": symbol,
                "page": page,
                "url": url,
                "http_status": 200,
                "bytes": len(raw),
                "rows": len(rows),
                "first_date": dates[0] if dates else "",
                "last_date": dates[-1] if dates else "",
                "sha256": hashlib.sha256(raw).hexdigest(),
            })
            for row in rows:
                key = (symbol, date_of(row))
                if key in history:
                    raise RuntimeError(f"duplicate history row: {key}")
                history[key] = row

    with (ROOT / "manifest.csv").open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=manifest[0].keys())
        writer.writeheader()
        writer.writerows(manifest)

    issue_rows = list(csv.DictReader(ISSUE_CSV.open(encoding="utf-8-sig", newline="")))
    coverage: list[dict] = []
    counts: Counter[str] = Counter()
    zero_issue_counts: Counter[str] = Counter()
    positive_candidates: list[dict] = []
    for issue in issue_rows:
        row = history.get((issue["symbol"], issue["trade_date"]))
        present = row is not None
        volume = int(float(row.get("volume", 0))) if present else None
        positive = present and volume > 0
        existing_alt = issue.get("existing_alt_positive", "").lower() == "true"
        if positive:
            classification = "POSITIVE_UNSPLIT_VOLUME"
        elif present:
            classification = "ZERO_VOLUME"
        else:
            classification = "NO_ROW"
        counts[classification] += 1
        if positive and existing_alt:
            counts["POSITIVE_OVERLAPS_EXISTING_ALTERNATE"] += 1
        elif positive:
            counts["POSITIVE_WITHOUT_EXISTING_ALTERNATE"] += 1
        is_zero_issue = issue["issue_categories"] == "ZERO_VOLUME_UNVERIFIED"
        if is_zero_issue:
            zero_issue_counts[classification] += 1
            if positive and existing_alt:
                zero_issue_counts["POSITIVE_OVERLAPS_EXISTING_ALTERNATE"] += 1
            elif positive:
                zero_issue_counts["POSITIVE_WITHOUT_EXISTING_ALTERNATE"] += 1
            if positive:
                positive_candidates.append({
                    "symbol": issue["symbol"],
                    "trade_date": issue["trade_date"],
                    "simplize_volume": volume,
                    "existing_alt_positive": existing_alt,
                    "cafef_classification": issue.get("cafef_classification", ""),
                    "cafef_matched_volume": issue.get("cafef_matched_volume", ""),
                    "cafef_negotiated_volume": issue.get("cafef_negotiated_volume", ""),
                })
        coverage.append({
            "symbol": issue["symbol"],
            "trade_date": issue["trade_date"],
            "issue_categories": issue["issue_categories"],
            "simplize_row_present": present,
            "simplize_volume": volume if present else "",
            "simplize_classification": classification,
            "existing_alt_positive": existing_alt,
            "cafef_classification": issue.get("cafef_classification", ""),
            "cafef_matched_volume": issue.get("cafef_matched_volume", ""),
            "cafef_negotiated_volume": issue.get("cafef_negotiated_volume", ""),
        })

    with (ROOT / "issue-coverage.csv").open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=coverage[0].keys())
        writer.writeheader()
        writer.writerows(coverage)

    with (ROOT / "positive-unsplit-issue-dates.csv").open(
        "w", newline="", encoding="utf-8"
    ) as f:
        writer = csv.DictWriter(f, fieldnames=positive_candidates[0].keys())
        writer.writeheader()
        writer.writerows(positive_candidates)

    controls = {
        ("NAS", "2020-10-15"): 80,
        ("CDG", "2025-05-13"): 100,
        ("VFC", "2026-07-03"): 1,
        ("VNX", "2026-07-28"): 100,
        ("SNC", "2026-10-15"): 71,
    }
    control_rows = []
    for (symbol, trade_date), expected in controls.items():
        row = history.get((symbol, trade_date))
        control_rows.append({
            "symbol": symbol,
            "trade_date": trade_date,
            "reference_volume": expected,
            "simplize_row_present": row is not None,
            "simplize_volume": int(float(row.get("volume", 0))) if row else "",
        })
    with (ROOT / "known-trade-controls.csv").open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=control_rows[0].keys())
        writer.writeheader()
        writer.writerows(control_rows)

    summary = {
        "provider": "Simplize public historical quote API",
        "symbols": len(SYMBOLS),
        "pages": len(manifest),
        "rows": len(history),
        "issue_dates": len(issue_rows),
        "issue_date_counts": dict(sorted(counts.items())),
        "zero_volume_issue_dates": sum(
            1 for issue in issue_rows
            if issue["issue_categories"] == "ZERO_VOLUME_UNVERIFIED"
        ),
        "zero_volume_issue_counts": dict(sorted(zero_issue_counts.items())),
        "known_trade_controls": control_rows,
    }
    (ROOT / "summary.json").write_text(
        json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(json.dumps(summary, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
