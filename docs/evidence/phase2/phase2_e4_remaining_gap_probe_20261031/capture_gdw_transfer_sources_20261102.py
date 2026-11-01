"""Capture the official VSDC and HNX records for the GDW venue transition."""
from __future__ import annotations

import hashlib
import html
import json
import re
import time
from datetime import datetime, timezone
from html.parser import HTMLParser
from http.cookiejar import CookieJar
from pathlib import Path
from urllib.parse import urlencode
from urllib.request import HTTPCookieProcessor, Request, build_opener


HERE = Path(__file__).resolve().parent
OUT = HERE / "gdw_transfer_sources_capture_20261102"
VSDC_SEARCH_PAGE = "https://vsdc.vn/vi/tra-cuu-thong-ke/TK_MACK_CHUYENSAN?tab=4"
VSDC_SEARCH_POST = "https://vsdc.vn/mack-chuyensan/search"
VSDC_ARTICLE_URL = "https://vsdc.vn/ad1/51464"
HNX_UPCOM_REPORT = (
    "https://www.hnx.vn/ModuleReportStockETFs/"
    "Report_MD_TradingScale/ListData_UPCoM"
)
HNX_UPCOM_REFERER = (
    "https://www.hnx.vn/vi-vn/ModuleReportStockETFs/"
    "Report_MD_TradingScale/ListData_UPCoM"
)
REPORT_DATES = ("2018-12-06", "2018-12-07", "2018-12-10", "2018-12-11")


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


def sha256(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def extract_div(html_text: str, class_name: str) -> str:
    opening = re.search(
        rf"<div\b(?=[^>]*\bclass=['\"][^'\"]*\b{re.escape(class_name)}\b[^'\"]*['\"])[^>]*>",
        html_text,
        re.IGNORECASE,
    )
    if opening is None:
        raise ValueError(f"article response has no div with class {class_name!r}")
    remainder = html_text[opening.start() :]
    depth = 0
    for tag in re.finditer(r"</?div\b[^>]*>", remainder, re.IGNORECASE):
        if tag.group(0).startswith("</"):
            depth -= 1
        elif not tag.group(0).rstrip().endswith("/>"):
            depth += 1
        if depth == 0:
            return remainder[: tag.end()]
    raise ValueError(f"article div {class_name!r} is unbalanced")


def parse_int(text: str) -> int:
    digits = "".join(char for char in text if char.isdigit())
    return int(digits or "0")


def main() -> None:
    if OUT.exists():
        raise SystemExit(f"refusing to overwrite existing capture folder: {OUT}")
    OUT.mkdir(parents=True)
    opener = build_opener(HTTPCookieProcessor(CookieJar()))
    manifest: dict[str, object] = {
        "capture_time_utc": utc_now(),
        "tls_certificate_validation": "default urllib validation; no bypass",
        "symbol": "GDW",
        "isin": "VN000000GDW9",
        "vsdc": {},
        "hnx_upcom_daily_reports": [],
        "limitations": [
            "An absent row in a daily report is recorded as an absent row only.",
            "No individual session is classified as traded, no-trade, suspended, or delisted.",
        ],
    }

    page_request = Request(
        VSDC_SEARCH_PAGE,
        headers={"User-Agent": "Mozilla/5.0", "Accept": "text/html,*/*"},
    )
    with opener.open(page_request, timeout=30) as response:
        page_bytes = response.read()
        page_status = response.status
        page_final_url = response.geturl()
    page_text = page_bytes.decode("utf-8", errors="strict")
    token_match = re.search(
        r'<meta\s+name=["\']__VPToken["\']\s+content=["\']([^"\']+)["\']',
        page_text,
        re.IGNORECASE,
    )
    if page_status != 200 or token_match is None:
        raise RuntimeError("VSDC search page did not return its normal request token")
    request_token = token_match.group(1)

    search_body = json.dumps(
        {
            "SearchKey": "GDW|VI",
            "CurrentPage": 1,
            "RecordOnPage": 10,
            "OrderBy": "",
            "OrderType": "",
        },
        ensure_ascii=False,
        separators=(",", ":"),
    ).encode("utf-8")
    search_request = Request(
        VSDC_SEARCH_POST,
        data=search_body,
        headers={
            "Content-Type": "application/json;charset=utf-8",
            "Accept": "*/*",
            "Origin": "https://vsdc.vn",
            "Referer": VSDC_SEARCH_PAGE,
            "User-Agent": "Mozilla/5.0",
            "X-Requested-With": "XMLHttpRequest",
            "__VPToken": request_token,
        },
    )
    with opener.open(search_request, timeout=30) as response:
        search_bytes = response.read()
        search_status = response.status
        search_final_url = response.geturl()
    search_text = search_bytes.decode("utf-8", errors="strict")
    search_parser = TableRows()
    search_parser.feed(search_text)
    search_rows = [row for row in search_parser.rows if len(row) >= 8 and row[1] == "GDW"]
    if (
        search_status != 200
        or len(search_rows) != 1
        or search_rows[0][2] != "VN000000GDW9"
        or search_rows[0][4] != "UpCOM"
        or search_rows[0][5] != "HNX"
        or search_rows[0][6] != "11/12/2018"
        or "/ad1/51464" not in search_text
    ):
        raise RuntimeError("VSDC filtered row failed its GDW, venue, date, or article-link checks")
    search_path = OUT / "vsdc_gdw_transfer_search_result.html"
    search_path.write_bytes(search_bytes)

    article_request = Request(
        VSDC_ARTICLE_URL,
        headers={"User-Agent": "Mozilla/5.0", "Accept": "text/html,*/*"},
    )
    with opener.open(article_request, timeout=30) as response:
        article_bytes = response.read()
        article_status = response.status
        article_final_url = response.geturl()
    article_text = article_bytes.decode("utf-8", errors="strict")
    article_text_decoded = html.unescape(article_text)
    for required in ("GDW", "UPCOM", "HNX", "11/12/2018", "9.500.000"):
        if required.casefold() not in article_text_decoded.casefold():
            raise RuntimeError(f"VSDC article is missing required source text: {required}")
    article_section = extract_div(article_text, "container-small")
    article_section_bytes = article_section.encode("utf-8")
    article_path = OUT / "vsdc_gdw_transfer_article_content.html"
    article_path.write_bytes(article_section_bytes)
    manifest["vsdc"] = {
        "search_page_url": VSDC_SEARCH_PAGE,
        "search_page_final_url": page_final_url,
        "search_page_status": page_status,
        "search_page_response_bytes": len(page_bytes),
        "search_page_response_sha256": sha256(page_bytes),
        "search_post_url": VSDC_SEARCH_POST,
        "search_post_final_url": search_final_url,
        "search_post_status": search_status,
        "search_post_request_body": {
            "SearchKey": "GDW|VI",
            "CurrentPage": 1,
            "RecordOnPage": 10,
            "OrderBy": "",
            "OrderType": "",
        },
        "request_token_header_sent": True,
        "request_token_value_saved": False,
        "filtered_row": search_rows[0],
        "search_result_file": search_path.name,
        "search_result_bytes": len(search_bytes),
        "search_result_sha256": sha256(search_bytes),
        "article_url": VSDC_ARTICLE_URL,
        "article_final_url": article_final_url,
        "article_status": article_status,
        "article_full_response_bytes": len(article_bytes),
        "article_full_response_sha256": sha256(article_bytes),
        "article_full_response_saved": False,
        "article_content_file": article_path.name,
        "article_content_bytes": len(article_section_bytes),
        "article_content_sha256": sha256(article_section_bytes),
        "article_update_time": "2018-12-04 16:32:59",
        "effective_date": "2018-12-11",
        "registered_share_count": 9500000,
        "article_fields_checked": ["issuer", "GDW", "UPCOM", "HNX", "11/12/2018", "9.500.000"],
    }

    for date_text in REPORT_DATES:
        day = datetime.strptime(date_text, "%Y-%m-%d")
        day_ddmmyyyy = day.strftime("%d/%m/%Y")
        filter_value = f"{day_ddmmyyyy}|0|0|'GDW'|-1|{day_ddmmyyyy}|"
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
            HNX_UPCOM_REPORT,
            data=body,
            headers={
                "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8",
                "User-Agent": "Mozilla/5.0",
                "Accept": "text/html,application/xhtml+xml,*/*",
                "Referer": HNX_UPCOM_REFERER,
                "X-Requested-With": "XMLHttpRequest",
            },
        )
        with opener.open(request, timeout=30) as response:
            payload = response.read()
            status = response.status
            final_url = response.geturl()
        parser = TableRows()
        parser.feed(payload.decode("utf-8", errors="strict"))
        rows = [row for row in parser.rows if len(row) >= 19 and row[1] == "GDW"]
        if status != 200 or len(rows) > 1:
            raise RuntimeError(f"HNX response did not return a unique valid result for {date_text}")
        report_file = f"hnx_upcom_gdw_{date_text}.html"
        (OUT / report_file).write_bytes(payload)
        manifest["hnx_upcom_daily_reports"].append(
            {
                "source_page_url": HNX_UPCOM_REFERER,
                "request_url": HNX_UPCOM_REPORT,
                "final_url": final_url,
                "http_status": status,
                "request_filter": filter_value,
                "trade_date": date_text,
                "symbol": "GDW",
                "row_count": len(rows),
                "row_cells": rows[0] if rows else None,
                "total_market_volume": parse_int(rows[0][17]) if rows else None,
                "total_market_value_vnd": parse_int(rows[0][18]) if rows else None,
                "response_file": report_file,
                "response_bytes": len(payload),
                "response_sha256": sha256(payload),
            }
        )
        if date_text != REPORT_DATES[-1]:
            time.sleep(0.5)

    manifest["capture_complete_time_utc"] = utc_now()
    manifest_path = OUT / "capture_manifest.json"
    manifest_path.write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"Captured VSDC GDW transfer notice and {len(REPORT_DATES)} HNX daily reports.")
    for report in manifest["hnx_upcom_daily_reports"]:
        print(
            f"{report['trade_date']}: rows={report['row_count']} "
            f"total_market_volume={report['total_market_volume']} "
            f"sha256={report['response_sha256']}"
        )
    print(f"Manifest: {manifest_path}")


if __name__ == "__main__":
    main()
