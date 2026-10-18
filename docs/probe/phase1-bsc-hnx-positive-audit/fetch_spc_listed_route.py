"""Recheck SPC after using HNX's exact listed-market filter."""
from __future__ import annotations

import csv
import hashlib
import time
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urlencode
from urllib.request import Request, urlopen


ROOT = Path(__file__).resolve().parent
RAW = ROOT / "raw"
URL = "https://www.hnx.vn/ModuleReportStockETFs/Report_MD_TradingScale/ListData_Listed"
PAGE_URL = "https://www.hnx.vn/vi-vn/ModuleReportStockETFs/Report_MD_TradingScale/ListData_Listed"
SAMPLES = [
    {"trade_date": "2023-06-06", "bsc_matched_volume": 0, "bsc_negotiated_volume": 75_000},
    {"trade_date": "2026-10-15", "bsc_matched_volume": 400, "bsc_negotiated_volume": 0},
]


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


def to_int(value: str) -> int:
    digits = "".join(char for char in value if char.isdigit())
    return int(digits or "0")


def main() -> None:
    output = ROOT / "spc-listed-route-filter-fixed.csv"
    if output.exists():
        raise SystemExit("follow-up is already archived; refusing to overwrite it")
    RAW.mkdir(parents=True, exist_ok=True)
    results: list[dict[str, str | int]] = []

    for index, sample in enumerate(SAMPLES):
        trade_date = sample["trade_date"]
        date_filter = time.strftime("%d/%m/%Y", time.strptime(trade_date, "%Y-%m-%d"))
        filter_value = f"{date_filter}|0|0|'SPC'|0|{date_filter}"
        body = urlencode(
            {
                "p_keysearch": filter_value,
                "pColOrder": "",
                "pOrderType": "",
                "pCurrentPage": "1",
                "pRecordOnPage": "200",
                "pIsSearch": "1",
            }
        ).encode("ascii")
        request = Request(
            URL,
            data=body,
            headers={
                "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8",
                "User-Agent": "Mozilla/5.0",
                "Accept": "text/html,application/xhtml+xml,*/*",
                "Referer": PAGE_URL,
                "X-Requested-With": "XMLHttpRequest",
            },
        )
        with urlopen(request, timeout=30) as response:
            payload = response.read()
            status = response.status

        parser = TableRows()
        parser.feed(payload.decode("utf-8", errors="strict"))
        matches = [row for row in parser.rows if len(row) >= 19 and row[1] == "SPC"]
        row = matches[0] if len(matches) == 1 else []
        relative_file = f"raw/SPC-{trade_date}-HNX-listed-filter-fixed.html"
        (ROOT / relative_file).write_bytes(payload)
        hnx_matched = (
            to_int(row[9]) + to_int(row[11]) + to_int(row[13]) if row else ""
        )
        hnx_negotiated = to_int(row[15]) if row else ""
        results.append(
            {
                "symbol": "SPC",
                **sample,
                "report_route": "HNX-listed",
                "http_status": status,
                "record_count_for_symbol": len(matches),
                "hnx_matched_volume": hnx_matched,
                "hnx_negotiated_volume": hnx_negotiated,
                "matched_volume_equal": (
                    int(sample["bsc_matched_volume"]) == hnx_matched if row else ""
                ),
                "negotiated_volume_equal": (
                    int(sample["bsc_negotiated_volume"]) == hnx_negotiated if row else ""
                ),
                "source_url": URL,
                "filter": filter_value,
                "file": relative_file,
                "payload_sha256": hashlib.sha256(payload).hexdigest(),
            }
        )
        if index + 1 < len(SAMPLES):
            time.sleep(1.0)

    with output.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(results[0]))
        writer.writeheader()
        writer.writerows(results)
    print(f"Fetched {len(results)} exact-date HNX-listed SPC reports")


if __name__ == "__main__":
    main()
