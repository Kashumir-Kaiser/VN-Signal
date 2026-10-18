"""Fetch one deterministic, exact-date HNX report per affected symbol."""
from __future__ import annotations

import csv
import hashlib
import time
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urlencode
from urllib.request import Request, urlopen


ROOT = Path(__file__).resolve().parent
ISSUES = ROOT.parent / "phase1-partial-audit" / "issue-coverage.csv"
CAFEF_ISSUES = ROOT.parent / "phase1-cafef-history-audit" / "issue-coverage-cafef.csv"
HNX_SHC = ROOT.parent / "phase1-partial-audit" / "hnx-shc-evidence-import.csv"
RAW = ROOT / "raw"
URL = (
    "https://www.hnx.vn/ModuleReportStockETFs/"
    "Report_MD_TradingScale/ListData_UPCoM"
)
PAGE_URL = (
    "https://www.hnx.vn/vi-vn/ModuleReportStockETFs/"
    "Report_MD_TradingScale/ListData_UPCoM"
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


def choose_sample() -> list[dict[str, str]]:
    with ISSUES.open(encoding="utf-8-sig", newline="") as stream:
        rows = list(csv.DictReader(stream))
    with CAFEF_ISSUES.open(encoding="utf-8-sig", newline="") as stream:
        cafef = {
            (row["symbol"], row["trade_date"]): row["cafef_classification"]
            for row in csv.DictReader(stream)
        }
    with HNX_SHC.open(encoding="utf-8-sig", newline="") as stream:
        prior_hnx_no_match = {
            (row["symbol"], row["trade_date"])
            for row in csv.DictReader(stream)
            if to_int(row["total_matched_volume"]) == 0
        }
    unresolved = [
        row
        for row in rows
        if row["issue_categories"] == "ZERO_VOLUME_UNVERIFIED"
        and (not row["vndirect_v"] or to_int(row["vndirect_v"]) == 0)
        and (not row["dnse_v"] or to_int(row["dnse_v"]) == 0)
        and cafef.get((row["symbol"], row["trade_date"]))
        in {"ZERO_VOLUME", "NO_POSITIVE_SOURCE_ROW"}
        and (row["symbol"], row["trade_date"]) not in prior_hnx_no_match
    ]
    sample: list[dict[str, str]] = []
    for symbol in sorted({row["symbol"] for row in unresolved}):
        symbol_rows = sorted(
            (row for row in unresolved if row["symbol"] == symbol),
            key=lambda row: row["trade_date"],
        )
        sample.append(symbol_rows[(len(symbol_rows) - 1) // 2])
    return sample


def main() -> None:
    if (ROOT / "sample-results.csv").exists():
        raise SystemExit("sample is already archived; use a new evidence folder for another check")
    RAW.mkdir(parents=True, exist_ok=True)
    if any(RAW.iterdir()):
        raise SystemExit("raw report folder is not empty; refusing to overwrite archived bytes")
    evidence: list[dict[str, str | int]] = []
    sample = choose_sample()
    for index, issue in enumerate(sample):
        symbol = issue["symbol"]
        trade_date = issue["trade_date"]
        date_filter = time.strftime("%d/%m/%Y", time.strptime(trade_date, "%Y-%m-%d"))
        filter_value = f"{date_filter}|0|0|'{symbol}'|-1|{date_filter}|"
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
        path = RAW / f"{symbol}-{trade_date}.html"
        path.write_bytes(payload)
        digest = hashlib.sha256(payload).hexdigest()

        parser = TableRows()
        parser.feed(payload.decode("utf-8", errors="strict"))
        matches = [row for row in parser.rows if len(row) >= 19 and row[1] == symbol]
        row = matches[0] if len(matches) == 1 else []
        evidence.append(
            {
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
                "file": str(path.relative_to(ROOT)).replace("\\", "/"),
                "payload_sha256": digest,
            }
        )
        if index + 1 < len(sample):
            time.sleep(1.0)

    output = ROOT / "sample-results.csv"
    with output.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(evidence[0]))
        writer.writeheader()
        writer.writerows(evidence)
    print(f"Fetched {len(evidence)} exact-date HNX reports; wrote {output.name}")


if __name__ == "__main__":
    main()
