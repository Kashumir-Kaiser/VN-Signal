"""Fetch one exact-date HNX positive-volume check for each BSC-covered symbol."""
from __future__ import annotations

import csv
import hashlib
import time
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urlencode
from urllib.request import Request, urlopen


ROOT = Path(__file__).resolve().parent
ISSUES = ROOT.parent / "phase1-easystock-history-audit" / "issue-coverage.csv"
BSC = ROOT.parent / "phase1-bsc-history-audit" / "daily-activity.csv"
RAW = ROOT / "raw"
URL = (
    "https://www.hnx.vn/ModuleReportStockETFs/"
    "Report_MD_TradingScale/ListData_UPCoM"
)
PAGE_URL = (
    "https://www.hnx.vn/vi-vn/ModuleReportStockETFs/"
    "Report_MD_TradingScale/ListData_UPCoM"
)
LISTED_URL = (
    "https://www.hnx.vn/ModuleReportStockETFs/"
    "Report_MD_TradingScale/ListData_Listed"
)
LISTED_PAGE_URL = (
    "https://www.hnx.vn/vi-vn/ModuleReportStockETFs/"
    "Report_MD_TradingScale/ListData_Listed"
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


def choose_sample() -> list[dict[str, str | int]]:
    with ISSUES.open(encoding="utf-8-sig", newline="") as stream:
        issue_rows = {
            (row["symbol"], row["trade_date"]): row
            for row in csv.DictReader(stream)
        }
    with BSC.open(encoding="utf-8-sig", newline="") as stream:
        bsc_rows = list(csv.DictReader(stream))

    by_symbol: dict[str, list[dict[str, str | int]]] = {}
    for row in bsc_rows:
        key = (row["symbol"], row["trade_date"])
        issue = issue_rows.get(key)
        volume = to_int(row["negotiated_volume"])
        if issue and volume:
            by_symbol.setdefault(row["symbol"], []).append(
                {
                    "symbol": row["symbol"],
                    "trade_date": row["trade_date"],
                    "bsc_negotiated_volume": volume,
                    "cafef_classification": issue["cafef_classification"],
                    "easy_stock_row_present": issue["easystock_row_present"],
                }
            )

    # Use the largest reported deal per symbol to make the validation value legible.
    return [
        max(rows, key=lambda row: int(row["bsc_negotiated_volume"]))
        for _, rows in sorted(by_symbol.items())
    ]


def main() -> None:
    output = ROOT / "sample-results.csv"
    if output.exists():
        raise SystemExit("sample is already archived; refusing to overwrite it")
    RAW.mkdir(parents=True, exist_ok=True)
    if any(RAW.iterdir()):
        raise SystemExit("raw report folder is not empty; refusing to overwrite bytes")

    sample = choose_sample()
    if not sample:
        raise SystemExit("no BSC negotiated-volume sample dates found")

    evidence: list[dict[str, str | int]] = []
    for index, candidate in enumerate(sample):
        symbol = str(candidate["symbol"])
        trade_date = str(candidate["trade_date"])
        listed = symbol == "SPC" and trade_date >= "2022-01-21"
        route = "HNX-listed" if listed else "UPCoM"
        source_url = LISTED_URL if listed else URL
        referer = LISTED_PAGE_URL if listed else PAGE_URL
        date_filter = time.strftime("%d/%m/%Y", time.strptime(trade_date, "%Y-%m-%d"))
        filter_value = (
            f"{date_filter}|0|0|'{symbol}'|0|{date_filter}"
            if listed
            else f"{date_filter}|0|0|'{symbol}'|-1|{date_filter}|"
        )
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
            source_url,
            data=body,
            headers={
                "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8",
                "User-Agent": "Mozilla/5.0",
                "Accept": "text/html,application/xhtml+xml,*/*",
                "Referer": referer,
                "X-Requested-With": "XMLHttpRequest",
            },
        )
        with urlopen(request, timeout=30) as response:
            payload = response.read()
            status = response.status

        parser = TableRows()
        parser.feed(payload.decode("utf-8", errors="strict"))
        matches = [row for row in parser.rows if len(row) >= 19 and row[1] == symbol]
        row = matches[0] if len(matches) == 1 else []
        relative_file = f"raw/{symbol}-{trade_date}-{route}.html"
        (ROOT / relative_file).write_bytes(payload)
        evidence.append(
            {
                **candidate,
                "http_status": status,
                "record_count_for_symbol": len(matches),
                "hnx_negotiated_volume": to_int(row[15]) if row else "",
                "hnx_negotiated_value_vnd": to_int(row[16]) if row else "",
                "hnx_total_market_volume": to_int(row[17]) if row else "",
                "hnx_total_market_value_vnd": to_int(row[18]) if row else "",
                "report_route": route,
                "source_url": source_url,
                "filter": filter_value,
                "file": relative_file,
                "payload_sha256": hashlib.sha256(payload).hexdigest(),
            }
        )
        if index + 1 < len(sample):
            time.sleep(1.0)

    with output.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(evidence[0]))
        writer.writeheader()
        writer.writerows(evidence)
    print(f"Fetched {len(evidence)} exact-date HNX reports into {ROOT}")


if __name__ == "__main__":
    main()
