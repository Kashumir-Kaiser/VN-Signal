"""Reconcile CafeF public annual exports with the existing VCI issue-date audit."""

from __future__ import annotations

import csv
import datetime as dt
import hashlib
import json
from collections import Counter, defaultdict
from decimal import Decimal, InvalidOperation
from pathlib import Path

from openpyxl import load_workbook


HERE = Path(__file__).resolve().parent
RAW = HERE / "raw"
ISSUES = HERE.parent / "phase1-partial-audit" / "issue-coverage.csv"
MANIFEST = HERE / "manifest.csv"
DETAIL_OUT = HERE / "issue-coverage-cafef.csv"
SYMBOL_OUT = HERE / "symbol-summary.csv"
DAILY_OUT = HERE / "daily-activity.csv"
SUMMARY_OUT = HERE / "summary.json"


def parse_date(value: object) -> dt.date:
    if isinstance(value, dt.datetime):
        return value.date()
    if isinstance(value, dt.date):
        return value
    return dt.datetime.strptime(str(value).strip(), "%d/%m/%Y").date()


def parse_volume(value: object) -> Decimal:
    if value is None or value == "":
        return Decimal(0)
    if isinstance(value, (int, float, Decimal)):
        return Decimal(str(value))
    text = str(value).strip().replace(",", "")
    try:
        return Decimal(text)
    except InvalidOperation as exc:
        raise ValueError(f"Unparseable volume cell: {value!r}") from exc


def positive_flag(value: str) -> bool:
    return value.strip().lower() in {"t", "true", "1", "yes"}


def hash_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest().upper()


def load_cafef_rows() -> tuple[dict[tuple[str, dt.date], dict[str, object]], dict[str, dict[str, object]]]:
    source_rows: dict[tuple[str, dt.date], dict[str, object]] = {}
    workbooks: dict[str, dict[str, object]] = {}
    with MANIFEST.open(encoding="utf-8-sig", newline="") as handle:
        manifest_rows = list(csv.DictReader(handle))
    if len(manifest_rows) != 144:
        raise ValueError(f"Expected 144 annual export entries, got {len(manifest_rows)}")

    for manifest in manifest_rows:
        symbol = manifest["symbol"].strip().upper()
        year = int(manifest["year"])
        if manifest["status"] not in {"OK", "EXISTING"}:
            raise ValueError(f"Export failed for {symbol}/{year}: {manifest['error']}")
        path = RAW / f"{symbol}-{year}.xlsx"
        if not path.is_file():
            raise FileNotFoundError(path)
        actual_hash = hash_file(path)
        if actual_hash != manifest["sha256"].upper():
            raise ValueError(f"Manifest hash mismatch for {path.name}")

        workbook = load_workbook(path, read_only=True, data_only=True)
        sheet = workbook.active
        values = sheet.iter_rows(values_only=True)
        header = next(values)
        columns = {str(name).strip(): index for index, name in enumerate(header) if name is not None}
        needed = {"Mã", "Ngày", "Khối lượng khớp lệnh", "Khối lượng thỏa thuận"}
        if not needed.issubset(columns):
            raise ValueError(f"Unexpected CafeF columns in {path.name}: {tuple(columns)}")

        count = 0
        for cells in values:
            if not cells or all(cell is None for cell in cells):
                continue
            row_symbol = str(cells[columns["Mã"]]).strip().upper()
            if row_symbol != symbol:
                raise ValueError(f"Symbol mismatch in {path.name}: {row_symbol}")
            trade_date = parse_date(cells[columns["Ngày"]])
            if trade_date.year != year:
                raise ValueError(f"Date outside requested year in {path.name}: {trade_date}")
            key = (symbol, trade_date)
            if key in source_rows:
                raise ValueError(f"Duplicate CafeF row across exports: {key}")
            source_rows[key] = {
                "matched_volume": parse_volume(cells[columns["Khối lượng khớp lệnh"]]),
                "negotiated_volume": parse_volume(cells[columns["Khối lượng thỏa thuận"]]),
                "matched_value": cells[columns["Giá trị khớp lệnh"]],
                "negotiated_value": cells[columns["Giá trị thỏa thuận"]],
                "open": cells[columns["Giá mở cửa"]],
                "high": cells[columns["Giá cao nhất"]],
                "low": cells[columns["Giá thấp nhất"]],
                "close_reported": cells[columns["Giá đóng cửa"]],
                "close_adjusted": cells[columns["Giá điều chỉnh"]],
                "file": path.name,
                "sha256": actual_hash,
                "source_row": count,
                "exchange": manifest["exchange"],
            }
            count += 1
        workbook.close()
        workbooks[f"{symbol}-{year}"] = {
            "rows": count,
            "sha256": actual_hash,
            "bytes": path.stat().st_size,
            "exchange": manifest["exchange"],
        }
    return source_rows, workbooks


def main() -> None:
    source_rows, workbooks = load_cafef_rows()
    with ISSUES.open(encoding="utf-8-sig", newline="") as handle:
        issues = list(csv.DictReader(handle))

    counts: Counter[str] = Counter()
    by_symbol: dict[str, Counter[str]] = defaultdict(Counter)
    latest_positive: dict[str, dt.date] = {}
    detail_rows: list[dict[str, object]] = []

    for issue in issues:
        symbol = issue["symbol"].strip().upper()
        trade_date = dt.date.fromisoformat(issue["trade_date"])
        row = source_rows.get((symbol, trade_date))
        alt_positive = positive_flag(issue["vndirect_positive_traded"]) or positive_flag(
            issue["dnse_positive_traded"]
        )
        matched = row["matched_volume"] if row else None
        negotiated = row["negotiated_volume"] if row else None
        if row is None:
            classification = "ABSENT"
        elif matched > 0:
            classification = "POSITIVE_MATCHED"
        elif negotiated > 0:
            classification = "POSITIVE_NEGOTIATED_ONLY"
        else:
            classification = "ZERO_VOLUME"

        cafe_positive = classification.startswith("POSITIVE_")
        if cafe_positive and alt_positive:
            cross_class = "CAFEF_AND_EXISTING_ALT"
        elif cafe_positive:
            cross_class = "CAFEF_ONLY_POSITIVE"
        elif alt_positive:
            cross_class = "EXISTING_ALT_ONLY_POSITIVE"
        else:
            cross_class = "NO_POSITIVE_SOURCE_ROW"

        counts[classification] += 1
        counts[cross_class] += 1
        by_symbol[symbol][classification] += 1
        by_symbol[symbol][cross_class] += 1
        if cafe_positive:
            latest_positive[symbol] = max(latest_positive.get(symbol, trade_date), trade_date)

        detail_rows.append(
            {
                "symbol": symbol,
                "exchange": issue["exchange"],
                "trade_date": trade_date.isoformat(),
                "issue_categories": issue["issue_categories"],
                "cafef_row_present": row is not None,
                "cafef_matched_volume": matched,
                "cafef_negotiated_volume": negotiated,
                "cafef_total_volume": (matched + negotiated) if row else None,
                "cafef_classification": classification,
                "vndirect_positive_traded": issue["vndirect_positive_traded"],
                "dnse_positive_traded": issue["dnse_positive_traded"],
                "existing_alt_positive": alt_positive,
                "cross_source_classification": cross_class,
                "cafef_file": row["file"] if row else "",
                "cafef_source_row": row["source_row"] if row else "",
                "cafef_sha256": row["sha256"] if row else "",
            }
        )

    with DETAIL_OUT.open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(detail_rows[0]))
        writer.writeheader()
        writer.writerows(detail_rows)

    symbols = sorted({row["symbol"] for row in issues})
    symbol_rows = []
    for symbol in symbols:
        subset = [row for row in detail_rows if row["symbol"] == symbol]
        zero_subset = [row for row in subset if "ZERO_VOLUME" in row["issue_categories"]]
        latest_date = latest_positive.get(symbol)
        symbol_rows.append(
            {
                "symbol": symbol,
                "issue_dates": len(subset),
                "zero_volume_issue_dates": len(zero_subset),
                "positive_matched": by_symbol[symbol]["POSITIVE_MATCHED"],
                "positive_negotiated_only": by_symbol[symbol]["POSITIVE_NEGOTIATED_ONLY"],
                "zero_volume_rows": by_symbol[symbol]["ZERO_VOLUME"],
                "absent_rows": by_symbol[symbol]["ABSENT"],
                "cafef_only_positive": by_symbol[symbol]["CAFEF_ONLY_POSITIVE"],
                "positive_overlaps_existing_alt": by_symbol[symbol]["CAFEF_AND_EXISTING_ALT"],
                "existing_alt_only_positive": by_symbol[symbol]["EXISTING_ALT_ONLY_POSITIVE"],
                "zero_cafef_positive_matched": sum(r["cafef_classification"] == "POSITIVE_MATCHED" for r in zero_subset),
                "zero_cafef_positive_negotiated_only": sum(r["cafef_classification"] == "POSITIVE_NEGOTIATED_ONLY" for r in zero_subset),
                "zero_cafef_zero_volume": sum(r["cafef_classification"] == "ZERO_VOLUME" for r in zero_subset),
                "zero_cafef_absent": sum(r["cafef_classification"] == "ABSENT" for r in zero_subset),
                "zero_cafef_only_positive": sum(r["cross_source_classification"] == "CAFEF_ONLY_POSITIVE" for r in zero_subset),
                "zero_cafef_overlap_alt_positive": sum(r["cross_source_classification"] == "CAFEF_AND_EXISTING_ALT" for r in zero_subset),
                "zero_existing_alt_only_positive": sum(r["cross_source_classification"] == "EXISTING_ALT_ONLY_POSITIVE" for r in zero_subset),
                "latest_cafef_positive_issue_date": latest_date.isoformat() if latest_date else "",
            }
        )

    with SYMBOL_OUT.open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(symbol_rows[0]))
        writer.writeheader()
        writer.writerows(symbol_rows)

    daily_rows = []
    for (symbol, trade_date), row in sorted(source_rows.items()):
        daily_rows.append(
            {
                "source": "cafef",
                "symbol": symbol,
                "exchange": row["exchange"],
                "trade_date": trade_date.isoformat(),
                "open_thousand_vnd": row["open"],
                "high_thousand_vnd": row["high"],
                "low_thousand_vnd": row["low"],
                "close_reported_thousand_vnd": row["close_reported"],
                "close_adjusted_thousand_vnd": row["close_adjusted"],
                "matched_volume_shares": row["matched_volume"],
                "matched_value_billion_vnd": row["matched_value"],
                "negotiated_volume_shares": row["negotiated_volume"],
                "negotiated_value_billion_vnd": row["negotiated_value"],
                "source_file": row["file"],
                "source_row": row["source_row"],
                "source_sha256": row["sha256"],
            }
        )
    with DAILY_OUT.open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(daily_rows[0]))
        writer.writeheader()
        writer.writerows(daily_rows)

    zero_rows = [row for row in detail_rows if "ZERO_VOLUME" in row["issue_categories"]]
    zero_issue_counts = Counter(row["cafef_classification"] for row in zero_rows)
    zero_cross_counts = Counter(row["cross_source_classification"] for row in zero_rows)
    summary = {
        "source": "CafeF public historical price export",
        "retrieved_date": dt.date.today().isoformat(),
        "scope_issue_dates": len(issues),
        "zero_volume_issue_dates": len(zero_rows),
        "issue_symbols": symbols,
        "source_rows_in_annual_exports": len(source_rows),
        "daily_csv_rows": len(daily_rows),
        "annual_xlsx_files": len(workbooks),
        "annual_xlsx_bytes": sum(item["bytes"] for item in workbooks.values()),
        "issue_classifications": {
            key: value for key, value in sorted(counts.items()) if key in {
                "POSITIVE_MATCHED", "POSITIVE_NEGOTIATED_ONLY", "ZERO_VOLUME", "ABSENT"
            }
        },
        "cross_source_classifications": {
            key: value for key, value in sorted(counts.items()) if key in {
                "CAFEF_AND_EXISTING_ALT", "CAFEF_ONLY_POSITIVE",
                "EXISTING_ALT_ONLY_POSITIVE", "NO_POSITIVE_SOURCE_ROW"
            }
        },
        "zero_volume_issue_classifications": dict(sorted(zero_issue_counts.items())),
        "zero_volume_cross_source_classifications": dict(sorted(zero_cross_counts.items())),
        "per_symbol": symbol_rows,
        "limitations": [
            "A positive CafeF matched or negotiated volume is alternate-source execution evidence.",
            "A CafeF zero or absent row does not independently prove that no trade occurred.",
            "Only CafeF volume fields were used in this issue-date reconciliation; price fields were not imported.",
            "CafeF history is a secondary source and its export is not an exchange audit record.",
        ],
    }
    SUMMARY_OUT.write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({
        "scope_issue_dates": summary["scope_issue_dates"],
        "source_rows": summary["source_rows_in_annual_exports"],
        "daily_csv_rows": summary["daily_csv_rows"],
        "zero_volume_issue_dates": summary["zero_volume_issue_dates"],
        "annual_xlsx_files": summary["annual_xlsx_files"],
        "zero_volume_issue_classifications": summary["zero_volume_issue_classifications"],
        "zero_volume_cross_source_classifications": summary["zero_volume_cross_source_classifications"],
        "issue_classifications": summary["issue_classifications"],
        "cross_source_classifications": summary["cross_source_classifications"],
    }, ensure_ascii=True, indent=2))


if __name__ == "__main__":
    main()
