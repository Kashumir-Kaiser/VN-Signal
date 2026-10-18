"""Validate archived SHC HNX reports and emit an import CSV with exact HTML bytes."""
from __future__ import annotations

import base64
import csv
import hashlib
from html.parser import HTMLParser
from pathlib import Path


ROOT = Path(__file__).resolve().parent
REPORTS = {
    "2026-09-16": "ffd746c451e5086aaf47448ff7e99c3aa5a37e0ba67070220b256d4db487cb59",
    "2026-09-18": "1d696451236e8788f9abe603431652f9d157f1e88a7fde749ee630bfc101a739",
    "2026-09-21": "b29d6e3fd592bb33218f689000ae5c86ce7caf841b97384296dd16914a039cca",
}
SOURCE_URL = (
    "https://www.hnx.vn/vi-vn/ModuleReportStockETFs/"
    "Report_MD_TradingScale/ListData_UPCoM"
)
OUTPUT = ROOT / "hnx-shc-evidence-import.csv"


class TableRows(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.rows: list[list[str]] = []
        self.row: list[str] | None = None
        self.cell: list[str] | None = None

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if tag == "tr":
            self.row = []
        elif tag in {"td", "th"} and self.row is not None:
            self.cell = []

    def handle_data(self, data: str) -> None:
        if self.cell is not None:
            self.cell.append(data)

    def handle_endtag(self, tag: str) -> None:
        if tag in {"td", "th"} and self.cell is not None and self.row is not None:
            self.row.append(" ".join("".join(self.cell).split()))
            self.cell = None
        elif tag == "tr" and self.row is not None:
            self.rows.append(self.row)
            self.row = None


def integer(cell: str) -> int:
    digits = "".join(ch for ch in cell if ch.isdigit())
    return int(digits or "0")


def main() -> None:
    records: list[dict[str, str | int]] = []
    for trade_date, expected_sha in REPORTS.items():
        path = ROOT / "hnx-recent" / f"SHC-{trade_date}.html"
        body = path.read_bytes()
        actual_sha = hashlib.sha256(body).hexdigest()
        if actual_sha != expected_sha:
            raise SystemExit(f"{path.name}: archived SHA-256 mismatch")

        table = TableRows()
        table.feed(body.decode("utf-8", errors="strict"))
        matches = [row for row in table.rows if len(row) >= 19 and row[1] == "SHC"]
        if len(matches) != 1:
            raise SystemExit(f"{path.name}: expected one SHC data row, found {len(matches)}")
        row = matches[0]
        record = {
            "symbol": "SHC",
            "market": "UPCOM",
            "trade_date": trade_date,
            "source_row": integer(row[0]) - 1,
            "buy_order_count": integer(row[3]),
            "buy_order_volume": integer(row[4]),
            "sell_order_count": integer(row[6]),
            "sell_order_volume": integer(row[7]),
            "total_matched_volume": integer(row[17]),
            "total_matched_value_vnd": integer(row[18]),
            "source_url": SOURCE_URL,
            "payload_sha256": actual_sha,
            "payload_base64": base64.b64encode(body).decode("ascii"),
        }
        if record["total_matched_volume"] != 0 or record["total_matched_value_vnd"] != 0:
            raise SystemExit(f"{path.name}: expected explicit zero total, got {record}")
        records.append(record)

    fields = list(records[0])
    with OUTPUT.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=fields)
        writer.writeheader()
        writer.writerows(records)
    print(f"Validated {len(records)} archived HNX rows; wrote {OUTPUT.name}")


if __name__ == "__main__":
    main()
