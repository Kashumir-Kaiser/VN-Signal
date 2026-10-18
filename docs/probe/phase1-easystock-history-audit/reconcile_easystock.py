#!/usr/bin/env python3
"""Reconcile archived EasyStock JSON with the CafeF/alternate-source issue audit."""

from __future__ import annotations

import csv
import hashlib
import json
from collections import Counter
from pathlib import Path


ROOT = Path(__file__).resolve().parent
REPO = ROOT.parents[2]
RAW = ROOT / "raw"
BASELINE = REPO / "docs/probe/phase1-cafef-history-audit/issue-coverage-cafef.csv"


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open(encoding="utf-8-sig", newline="") as stream:
        return list(csv.DictReader(stream))


def write_csv(path: Path, columns: list[str], rows: list[dict[str, object]]) -> None:
    with path.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=columns)
        writer.writeheader()
        writer.writerows(rows)


manifest = read_csv(ROOT / "manifest.csv")
history: dict[tuple[str, str], dict[str, object]] = {}
by_symbol: dict[str, list[dict[str, object]]] = {}
hash_by_symbol: dict[str, str] = {}

for item in manifest:
    symbol = item["symbol"]
    path = ROOT / item["file"]
    payload = path.read_bytes()
    digest = hashlib.sha256(payload).hexdigest()
    if digest != item["sha256"].lower():
        raise ValueError(f"SHA-256 mismatch for {path.name}")
    records = json.loads(payload)
    by_symbol[symbol] = records
    hash_by_symbol[symbol] = digest
    for record in records:
        key = (symbol, str(record["time"]))
        if key in history:
            raise ValueError(f"duplicate source date: {key}")
        history[key] = record

issues = [
    row
    for row in read_csv(BASELINE)
    if row["issue_categories"] == "ZERO_VOLUME_UNVERIFIED"
]
coverage: list[dict[str, object]] = []
summary: list[dict[str, object]] = []
totals = Counter()

for issue in issues:
    symbol, date = issue["symbol"], issue["trade_date"]
    record = history.get((symbol, date))
    if record is None:
        classification = "ABSENT"
        volume: object = ""
        totals["issue_absent"] += 1
    else:
        volume = record.get("volume", "")
        if float(volume or 0) > 0:
            classification = "POSITIVE_VOLUME"
            totals["issue_positive"] += 1
        else:
            classification = "ZERO_VOLUME"
            totals["issue_zero"] += 1
    coverage.append(
        {
            "symbol": symbol,
            "trade_date": date,
            "issue_categories": issue["issue_categories"],
            "cafef_classification": issue["cafef_classification"],
            "existing_alt_positive": issue["existing_alt_positive"],
            "easystock_row_present": record is not None,
            "easystock_volume": volume,
            "easystock_classification": classification,
            "easystock_file": f"raw/{symbol}.json",
            "easystock_sha256": hash_by_symbol[symbol],
        }
    )

for symbol in sorted(by_symbol):
    records = by_symbol[symbol]
    dates = [str(row["time"]) for row in records]
    issue_rows = [row for row in coverage if row["symbol"] == symbol]
    source_positive = sum(float(row.get("volume") or 0) > 0 for row in records)
    issue_classes = Counter(row["easystock_classification"] for row in issue_rows)
    summary.append(
        {
            "symbol": symbol,
            "history_rows": len(records),
            "first_date": min(dates) if dates else "",
            "last_date": max(dates) if dates else "",
            "positive_volume_rows": source_positive,
            "zero_volume_rows": len(records) - source_positive,
            "vci_zero_volume_issue_dates": len(issue_rows),
            "issue_dates_absent": issue_classes["ABSENT"],
            "issue_dates_zero_volume": issue_classes["ZERO_VOLUME"],
            "issue_dates_positive_volume": issue_classes["POSITIVE_VOLUME"],
        }
    )

write_csv(
    ROOT / "issue-coverage.csv",
    [
        "symbol",
        "trade_date",
        "issue_categories",
        "cafef_classification",
        "existing_alt_positive",
        "easystock_row_present",
        "easystock_volume",
        "easystock_classification",
        "easystock_file",
        "easystock_sha256",
    ],
    coverage,
)
write_csv(
    ROOT / "symbol-summary.csv",
    [
        "symbol",
        "history_rows",
        "first_date",
        "last_date",
        "positive_volume_rows",
        "zero_volume_rows",
        "vci_zero_volume_issue_dates",
        "issue_dates_absent",
        "issue_dates_zero_volume",
        "issue_dates_positive_volume",
    ],
    summary,
)

positive_issue = sum(row["easystock_classification"] == "POSITIVE_VOLUME" for row in coverage)
unresolved = sum(
    row["easystock_classification"] != "POSITIVE_VOLUME"
    and row["existing_alt_positive"].lower() not in {"true", "t", "1", "yes"}
    and row["cafef_classification"] != "POSITIVE_MATCHED"
    and row["cafef_classification"] != "POSITIVE_NEGOTIATED_ONLY"
    and not (
        row["symbol"] == "SHC"
        and row["trade_date"] in {"2026-09-16", "2026-09-18", "2026-09-21"}
    )
    for row in coverage
)
result = {
    "symbols": len(by_symbol),
    "history_rows": sum(len(rows) for rows in by_symbol.values()),
    "positive_volume_rows": sum(
        float(row.get("volume") or 0) > 0
        for records in by_symbol.values()
        for row in records
    ),
    "zero_volume_issue_dates": totals["issue_zero"],
    "absent_issue_dates": totals["issue_absent"],
    "positive_volume_issue_dates": positive_issue,
    "cafef_negotiated_only_issue_dates": sum(
        row["cafef_classification"] == "POSITIVE_NEGOTIATED_ONLY" for row in coverage
    ),
    "issue_dates": len(issues),
    "unresolved_after_this_source": unresolved,
}
(ROOT / "summary.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
print(json.dumps(result, sort_keys=True))
