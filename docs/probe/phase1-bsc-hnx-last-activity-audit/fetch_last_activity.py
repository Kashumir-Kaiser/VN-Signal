"""Check the last positive BSC activity date for each partial-history ticker at HNX."""
from __future__ import annotations

import csv
import hashlib
import time
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urlencode
from urllib.request import Request, urlopen


ROOT = Path(__file__).resolve().parent
BSC = ROOT.parent / "phase1-bsc-history-audit" / "daily-activity.csv"
RAW = ROOT / "raw"
BASE = "https://www.hnx.vn/ModuleReportStockETFs/Report_MD_TradingScale"
UPCOM_PAGE = f"{BASE}/ListData_UPCoM"
LISTED_PAGE = f"{BASE}/ListData_Listed"


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


def latest_bsc_activity() -> list[dict[str, str | int]]:
    by_symbol: dict[str, list[dict[str, str | int]]] = {}
    with BSC.open(encoding="utf-8-sig", newline="") as stream:
        for row in csv.DictReader(stream):
            matched = to_int(row["matched_volume"])
            negotiated = to_int(row["negotiated_volume"])
            if matched or negotiated:
                by_symbol.setdefault(row["symbol"], []).append(
                    {
                        "symbol": row["symbol"],
                        "trade_date": row["trade_date"],
                        "bsc_matched_volume": matched,
                        "bsc_negotiated_volume": negotiated,
                    }
                )
    return [max(rows, key=lambda row: str(row["trade_date"])) for _, rows in sorted(by_symbol.items())]


def route_for(symbol: str, trade_date: str) -> tuple[str, str]:
    # SPC's HNX-listed trading replaced its UPCoM platform in January 2022.
    if symbol == "SPC" and trade_date >= "2022-01-21":
        return "HNX-listed", LISTED_PAGE
    return "UPCoM", UPCOM_PAGE


def main() -> None:
    output = ROOT / "last-activity-results.csv"
    if output.exists():
        raise SystemExit("sample is already archived; refusing to overwrite it")
    RAW.mkdir(parents=True, exist_ok=True)
    if any(RAW.iterdir()):
        raise SystemExit("raw report folder is not empty; refusing to overwrite bytes")

    results: list[dict[str, str | int]] = []
    samples = latest_bsc_activity()
    if len(samples) != 16:
        raise SystemExit(f"expected 16 symbol histories, found {len(samples)}")

    for index, item in enumerate(samples):
        symbol = str(item["symbol"])
        trade_date = str(item["trade_date"])
        route, url = route_for(symbol, trade_date)
        date_filter = time.strftime("%d/%m/%Y", time.strptime(trade_date, "%Y-%m-%d"))
        filter_value = (
            f"{date_filter}|0|0|'{symbol}'|0|{date_filter}"
            if route == "HNX-listed"
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
            url,
            data=body,
            headers={
                "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8",
                "User-Agent": "Mozilla/5.0",
                "Accept": "text/html,application/xhtml+xml,*/*",
                "Referer": url.replace("/ModuleReportStockETFs/", "/vi-vn/ModuleReportStockETFs/"),
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
        raw_name = f"{symbol}-{trade_date}-{route}.html"
        relative_file = f"raw/{raw_name}"
        (ROOT / relative_file).write_bytes(payload)

        continuous = to_int(row[9]) if row else 0
        closing = to_int(row[11]) if row else 0
        after_hours = to_int(row[13]) if row else 0
        negotiated = to_int(row[15]) if row else 0
        hnx_matched = continuous + closing + after_hours if row else ""
        hnx_market_total = to_int(row[17]) if row else ""
        results.append(
            {
                **item,
                "report_route": route,
                "http_status": status,
                "record_count_for_symbol": len(matches),
                "hnx_continuous_volume": continuous if row else "",
                "hnx_closing_auction_volume": closing if row else "",
                "hnx_after_hours_volume": after_hours if row else "",
                "hnx_matched_volume": hnx_matched,
                "hnx_negotiated_volume": negotiated if row else "",
                "hnx_total_market_volume": hnx_market_total,
                "bsc_hnx_matched_equal": (
                    int(item["bsc_matched_volume"]) == hnx_matched if row else ""
                ),
                "bsc_hnx_negotiated_equal": (
                    int(item["bsc_negotiated_volume"]) == negotiated if row else ""
                ),
                "source_url": url,
                "filter": filter_value,
                "file": relative_file,
                "payload_sha256": hashlib.sha256(payload).hexdigest(),
            }
        )
        if index + 1 < len(samples):
            time.sleep(1.0)

    with output.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(results[0]))
        writer.writeheader()
        writer.writerows(results)
    print(f"Fetched {len(results)} exact-date HNX latest-activity checks")


if __name__ == "__main__":
    main()
