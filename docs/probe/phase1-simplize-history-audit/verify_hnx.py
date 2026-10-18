"""Check Simplize-only positive UPCoM volumes against exact HNX daily reports."""

from __future__ import annotations

import csv
import hashlib
import time
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urlencode
from urllib.request import Request, urlopen


ROOT = Path(__file__).resolve().parent
RAW = ROOT / "hnx_raw"
URL = "https://www.hnx.vn/ModuleReportStockETFs/Report_MD_TradingScale/ListData_UPCoM"
PAGE_URL = "https://www.hnx.vn/vi-vn/ModuleReportStockETFs/Report_MD_TradingScale/ListData_UPCoM"
CONTROLS = (
    ("VNX", "2026-01-29"),
    ("VNX", "2026-01-30"),
    ("VNX", "2026-02-12"),
)


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
    RAW.mkdir(parents=True, exist_ok=True)

    evidence: list[dict[str, str | int]] = []
    for index, (symbol, trade_date) in enumerate(CONTROLS):
        path = RAW / f"{symbol}-{trade_date}.html"
        should_wait = not path.exists()
        date_filter = time.strftime("%d/%m/%Y", time.strptime(trade_date, "%Y-%m-%d"))
        filter_value = f"{date_filter}|0|0|'{symbol}'|-1|{date_filter}|"
        if path.exists():
            payload = path.read_bytes()
            status = 200
        else:
            body = urlencode({
                "p_keysearch": filter_value,
                "pColOrder": "",
                "pOrderType": "",
                "pCurrentPage": "1",
                "pRecordOnPage": "200",
                "pIsSearch": "1",
            }).encode("ascii")
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
            path.write_bytes(payload)

        parser = TableRows()
        parser.feed(payload.decode("utf-8", errors="strict"))
        matches = [row for row in parser.rows if len(row) >= 19 and row[1] == symbol]
        row = matches[0] if len(matches) == 1 else []
        evidence.append({
            "symbol": symbol,
            "trade_date": trade_date,
            "report_route": "UPCoM",
            "http_status": status,
            "record_count_for_symbol": len(matches),
            "buy_order_count": to_int(row[3]) if row else "",
            "buy_order_volume": to_int(row[4]) if row else "",
            "sell_order_count": to_int(row[6]) if row else "",
            "sell_order_volume": to_int(row[7]) if row else "",
            "total_matched_volume": to_int(row[17]) if row else "",
            "total_matched_value_vnd": to_int(row[18]) if row else "",
            "source_url": URL,
            "filter": filter_value,
            "file": path.name,
            "payload_sha256": hashlib.sha256(payload).hexdigest(),
        })
        if should_wait and index + 1 < len(CONTROLS):
            time.sleep(1.0)

    with (ROOT / "hnx-verification.csv").open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(evidence[0]))
        writer.writeheader()
        writer.writerows(evidence)
    print(f"Fetched {len(evidence)} targeted HNX reports")


if __name__ == "__main__":
    main()
