"""Reconcile the archived BSC pull to existing issue and HNX evidence."""
from __future__ import annotations

import csv
import json
from collections import Counter, defaultdict
from pathlib import Path


ROOT = Path(__file__).resolve().parent
PROBE = ROOT.parent
ISSUES = PROBE / "phase1-easystock-history-audit" / "issue-coverage.csv"
PARTIAL = PROBE / "phase1-partial-audit" / "issue-coverage.csv"
CAFEF = PROBE / "phase1-cafef-history-audit" / "daily-activity.csv"
MANIFEST = ROOT / "manifest.csv"
ACTIVITY = ROOT / "daily-activity.csv"
LAST_HNX = PROBE / "phase1-bsc-hnx-last-activity-audit" / "last-activity-results.csv"
SPC_HNX = (
    PROBE
    / "phase1-bsc-hnx-positive-audit"
    / "spc-listed-route-filter-fixed.csv"
)
POSITIVE_SAMPLE = (
    PROBE / "phase1-bsc-hnx-positive-audit" / "sample-results.csv"
)
SPC_POSITIVE = (
    PROBE
    / "phase1-bsc-hnx-positive-audit"
    / "spc-listed-route-filter-fixed.csv"
)
VNX_HNX = PROBE / "phase1-simplize-history-audit" / "hnx-verification.csv"
VNDIRECT_HNX = PROBE / "phase1-hnx-last-trade-audit" / "hnx-last-trade-reconciliation.csv"
OUTPUT_ISSUES = ROOT / "issue-coverage.csv"
OUTPUT_SYMBOLS = ROOT / "symbol-summary.csv"
OUTPUT_LATEST = ROOT / "latest-activity-reconciliation.csv"
OUTPUT_ANOMALIES = ROOT / "source-anomalies.csv"
OUTPUT_SUMMARY = ROOT / "summary.json"


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open(encoding="utf-8-sig", newline="") as stream:
        return list(csv.DictReader(stream))


def write_csv(path: Path, rows: list[dict[str, object]]) -> None:
    if not rows:
        raise ValueError(f"refusing to write empty output: {path}")
    with path.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def integer(value: str | None) -> int:
    return int((value or "0").replace(",", "").strip() or "0")


def activity_classification(matched: int, negotiated: int) -> str:
    if matched:
        return "POSITIVE_MATCHED"
    if negotiated:
        return "POSITIVE_NEGOTIATED_ONLY"
    return "ZERO_REPORTED_BY_BSC"


def main() -> None:
    issue_rows = read_csv(ISSUES)
    partial_rows = {
        (row["symbol"], row["trade_date"]): row for row in read_csv(PARTIAL)
    }
    cafe_rows = {
        (row["symbol"], row["trade_date"]): row for row in read_csv(CAFEF)
    }
    manifest = read_csv(MANIFEST)
    source_rows = read_csv(ACTIVITY)
    source_by_date: dict[tuple[str, str], dict[str, str]] = {}
    for row in source_rows:
        key = (row["symbol"], row["trade_date"])
        if key in source_by_date:
            raise ValueError(f"duplicate BSC symbol/date row: {key}")
        source_by_date[key] = row

    page_for: dict[tuple[str, str], dict[str, str]] = {}
    for row in manifest:
        first, last = sorted((row["first_date"], row["last_date"]))
        for date in (first, last):
            page_for[(row["symbol"], date)] = row
        for issue in issue_rows:
            if (
                issue["symbol"] == row["symbol"]
                and first <= issue["trade_date"] <= last
            ):
                page_for[(issue["symbol"], issue["trade_date"])] = row

    output_rows: list[dict[str, object]] = []
    symbol_counts: dict[str, Counter[str]] = defaultdict(Counter)
    summary: Counter[str] = Counter()

    zero_issue_rows = [
        row for row in issue_rows if row["issue_categories"] == "ZERO_VOLUME_UNVERIFIED"
    ]
    for issue in zero_issue_rows:
        key = (issue["symbol"], issue["trade_date"])
        bsc = source_by_date.get(key)
        partial = partial_rows.get(key, {})
        cafef = cafe_rows.get(key, {})
        if bsc is None:
            classification = "NO_BSC_ROW"
            matched = negotiated = 0
            summary["issue_rows_without_bsc_row"] += 1
            source_file = source_sha256 = source_page = ""
            close = matched_value = negotiated_value = opening = ceiling = floor = ""
        else:
            matched = integer(bsc["matched_volume"])
            negotiated = integer(bsc["negotiated_volume"])
            classification = activity_classification(matched, negotiated)
            page = page_for.get(key, {})
            source_file = page.get("raw_file", "")
            source_sha256 = page.get("response_sha256_utf8", "")
            source_page = page.get("page", "")
            close = bsc["close_price_thousand_vnd"]
            matched_value = bsc["matched_value_million_vnd"]
            negotiated_value = bsc["negotiated_value_million_vnd"]
            opening = bsc["open_price_thousand_vnd"]
            ceiling = bsc["ceiling_price_thousand_vnd"]
            floor = bsc["floor_price_thousand_vnd"]
            summary["issue_rows_with_bsc_row"] += 1

        symbol_counts[issue["symbol"]][classification] += 1
        summary[f"bsc_issue_{classification.lower()}"] += 1
        existing_alt_positive = issue["existing_alt_positive"].lower() == "true"
        if matched:
            summary["matched_positive_issue_rows"] += 1
            if not existing_alt_positive:
                summary["matched_issue_rows_not_in_existing_alt"] += 1
            vndirect_volume = integer(partial.get("vndirect_v"))
            dnse_volume = integer(partial.get("dnse_v"))
            if matched == vndirect_volume or matched == dnse_volume:
                summary["matched_volume_equals_existing_alt"] += 1
        if negotiated:
            summary["negotiated_positive_issue_rows"] += 1
            if issue["cafef_classification"] == "POSITIVE_NEGOTIATED_ONLY":
                summary["negotiated_issue_rows_also_in_cafef"] += 1
                if integer(cafef.get("negotiated_volume_shares")) == negotiated:
                    summary["negotiated_volume_equals_cafef"] += 1
            elif issue["cafef_classification"] == "ABSENT":
                summary["negotiated_issue_rows_absent_from_cafef"] += 1

        output_rows.append(
            {
                "symbol": issue["symbol"],
                "trade_date": issue["trade_date"],
                "issue_categories": issue["issue_categories"],
                "existing_alt_positive": issue["existing_alt_positive"],
                "cafef_classification": issue["cafef_classification"],
                "easystock_classification": issue["easystock_classification"],
                "easystock_volume": issue["easystock_volume"],
                "bsc_activity_classification": classification,
                "bsc_matched_volume": matched if bsc else "",
                "bsc_matched_value_million_vnd": matched_value,
                "bsc_negotiated_volume": negotiated if bsc else "",
                "bsc_negotiated_value_million_vnd": negotiated_value,
                "bsc_close_price_thousand_vnd": close,
                "bsc_open_price_thousand_vnd": opening,
                "bsc_ceiling_price_thousand_vnd": ceiling,
                "bsc_floor_price_thousand_vnd": floor,
                "bsc_raw_file": source_file,
                "bsc_page": source_page,
                "bsc_page_sha256": source_sha256,
            }
        )

    if len(zero_issue_rows) != 14_466:
        raise ValueError(f"expected 14,466 zero-volume issue dates, got {len(zero_issue_rows)}")

    symbols = []
    for symbol in sorted(symbol_counts):
        counts = symbol_counts[symbol]
        symbols.append(
            {
                "symbol": symbol,
                "issue_dates": sum(counts.values()),
                "bsc_matched_positive": counts["POSITIVE_MATCHED"],
                "bsc_negotiated_only": counts["POSITIVE_NEGOTIATED_ONLY"],
                "bsc_zero_reported": counts["ZERO_REPORTED_BY_BSC"],
                "bsc_row_missing": counts["NO_BSC_ROW"],
            }
        )

    # Exact HNX rows for every symbol's last BSC-positive activity date.
    latest_rows = {
        row["symbol"]: row for row in read_csv(LAST_HNX) if row["symbol"] != "SPC"
    }
    spc_latest = next(
        row
        for row in read_csv(SPC_HNX)
        if row["symbol"] == "SPC" and row["trade_date"] == "2026-10-15"
    )
    latest_rows["SPC"] = {
        "symbol": "SPC",
        "trade_date": spc_latest["trade_date"],
        "bsc_matched_volume": spc_latest["bsc_matched_volume"],
        "bsc_negotiated_volume": spc_latest["bsc_negotiated_volume"],
        "report_route": spc_latest["report_route"],
        "http_status": spc_latest["http_status"],
        "record_count_for_symbol": spc_latest["record_count_for_symbol"],
        "hnx_matched_volume": spc_latest["hnx_matched_volume"],
        "hnx_negotiated_volume": spc_latest["hnx_negotiated_volume"],
        "bsc_hnx_matched_equal": spc_latest["matched_volume_equal"],
        "bsc_hnx_negotiated_equal": spc_latest["negotiated_volume_equal"],
        "source_url": spc_latest["source_url"],
        "filter": spc_latest["filter"],
        "file": spc_latest["file"],
        "payload_sha256": spc_latest["payload_sha256"],
    }
    vndirect = {row["symbol"]: row for row in read_csv(VNDIRECT_HNX)}
    latest_activity: list[dict[str, object]] = []
    for symbol, row in sorted(latest_rows.items()):
        hnx_present = row["record_count_for_symbol"] == "1"
        match_equal = row["bsc_hnx_matched_equal"] == "True"
        deal_equal = row["bsc_hnx_negotiated_equal"] == "True"
        if not (hnx_present and match_equal and deal_equal):
            raise ValueError(f"latest BSC/HNX activity did not reconcile for {symbol}")
        matched = integer(row["bsc_matched_volume"])
        negotiated = integer(row["bsc_negotiated_volume"])
        vnd = vndirect[symbol]
        latest_activity.append(
            {
                "symbol": symbol,
                "latest_bsc_positive_date": row["trade_date"],
                "bsc_matched_volume": matched,
                "bsc_negotiated_volume": negotiated,
                "bsc_activity_type": "MATCHED" if matched else "NEGOTIATED_ONLY",
                "hnx_report_route": row["report_route"],
                "hnx_matched_volume": row["hnx_matched_volume"],
                "hnx_negotiated_volume": row["hnx_negotiated_volume"],
                "bsc_matches_hnx": True,
                "latest_vndirect_positive_matched_date": vnd["trade_date"],
                "latest_vndirect_matched_volume": vnd["expected_volume"],
                "bsc_activity_after_latest_vndirect_match": row["trade_date"] > vnd["trade_date"],
                "hnx_raw_file": (
                    f"../phase1-bsc-hnx-positive-audit/{row['file']}"
                    if symbol == "SPC"
                    else f"../phase1-bsc-hnx-last-activity-audit/{row['file']}"
                ),
                "hnx_payload_sha256": row["payload_sha256"],
            }
        )

    # A source row one calendar day before XMC's current HNX UPCoM profile date.
    anomalies = [
        {
            "symbol": row["symbol"],
            "trade_date": row["trade_date"],
            "bsc_matched_volume": integer(row["matched_volume"]),
            "bsc_negotiated_volume": integer(row["negotiated_volume"]),
            "hnx_profile_first_trading_date": "2019-06-28",
            "assessment": "pre-UPCoM-profile positive row; venue attribution unresolved",
            "source_page": page_for.get((row["symbol"], row["trade_date"]), {}).get("raw_file", ""),
        }
        for row in source_rows
        if row["symbol"] == "XMC"
        and row["trade_date"] == "2019-06-27"
        and (integer(row["matched_volume"]) or integer(row["negotiated_volume"]))
    ]

    # The 12 largest negotiated rows, stratified by ticker, also match HNX.
    positive_sample = [
        row for row in read_csv(POSITIVE_SAMPLE) if row["symbol"] != "SPC"
    ]
    corrected_spc_positive = next(
        row
        for row in read_csv(SPC_POSITIVE)
        if row["symbol"] == "SPC" and row["trade_date"] == "2023-06-06"
    )
    positive_sample_exact = sum(
        row["record_count_for_symbol"] == "1"
        and integer(row["bsc_negotiated_volume"]) == integer(row["hnx_negotiated_volume"])
        for row in positive_sample
    )
    positive_sample_exact += int(
        corrected_spc_positive["record_count_for_symbol"] == "1"
        and integer(corrected_spc_positive["bsc_negotiated_volume"])
        == integer(corrected_spc_positive["hnx_negotiated_volume"])
    )
    if len(positive_sample) != 11 or positive_sample_exact != 12:
        raise ValueError("BSC negotiated-volume HNX sample did not reconcile 12/12")

    # The three BSC-only CafeF rows are the three VNX HNX-confirmed deals.
    vnx_hnx = {
        (row["symbol"], row["trade_date"]): row for row in read_csv(VNX_HNX)
    }
    hnx_confirmed_cafef_absent = 0
    for issue in zero_issue_rows:
        key = (issue["symbol"], issue["trade_date"])
        bsc = source_by_date.get(key)
        if (
            bsc
            and integer(bsc["negotiated_volume"])
            and issue["cafef_classification"] == "ABSENT"
        ):
            hnx = vnx_hnx.get(key)
            if hnx and integer(hnx["negotiated_volume"]) == integer(bsc["negotiated_volume"]):
                hnx_confirmed_cafef_absent += 1
    new_activity_rows = (
        summary["matched_issue_rows_not_in_existing_alt"]
        + summary["negotiated_issue_rows_absent_from_cafef"]
        - hnx_confirmed_cafef_absent
    )

    summary_data = dict(summary)
    summary_data.update(
        {
            "retrieved_date": "2026-10-19",
            "source": "BSC public historical-data page",
            "source_history_rows": len(source_rows),
            "symbol_count": len(symbol_counts),
            "archived_page_count": len(manifest),
            "scope_from": "2018-10-01",
            "scope_to": "2026-10-16",
            "vci_zero_volume_issue_dates": len(zero_issue_rows),
            "issue_dates_with_bsc_row": summary["issue_rows_with_bsc_row"],
            "issue_dates_with_bsc_matched_activity": summary["matched_positive_issue_rows"],
            "issue_dates_with_bsc_negotiated_activity": summary["negotiated_positive_issue_rows"],
            "issue_dates_with_no_bsc_reported_activity": summary["bsc_issue_zero_reported_by_bsc"],
            "negotiated_cafef_absent_rows_confirmed_by_hnx": hnx_confirmed_cafef_absent,
            "bsc_activity_dates_not_previously_identified": new_activity_rows,
            "last_positive_activity_hnx_checks": len(latest_activity),
            "last_positive_activity_hnx_exact_matches": len(latest_activity),
            "large_negotiated_activity_hnx_sample_checks": len(positive_sample) + 1,
            "large_negotiated_activity_hnx_exact_matches": positive_sample_exact,
            "source_anomaly_count": len(anomalies),
            "limitations": [
                "BSC reports matching and negotiated transactions separately but does not provide daily high/low in this table.",
                "The 14,333 zero-volume BSC rows are not proof that no exchange activity occurred.",
                "A checked latest positive row is a verified activity date, not a certificate that no later trade was missed by BSC.",
                "Bulk storage and internal ML-use terms were not established from the public page.",
                "The XMC 2019-06-27 positive row predates its 2019-06-28 current UPCoM profile date; venue attribution remains unresolved.",
                "BSC data were preserved as a separate local evidence set and were not imported into canonical OHLCV bars.",
            ],
        }
    )

    write_csv(OUTPUT_ISSUES, output_rows)
    write_csv(OUTPUT_SYMBOLS, symbols)
    write_csv(OUTPUT_LATEST, latest_activity)
    write_csv(OUTPUT_ANOMALIES, anomalies)
    OUTPUT_SUMMARY.write_text(json.dumps(summary_data, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(summary_data, indent=2))


if __name__ == "__main__":
    main()
