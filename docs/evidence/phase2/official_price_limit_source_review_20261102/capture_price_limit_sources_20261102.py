#!/usr/bin/env python3
"""Capture official exchange price-limit rows for the 2019-01-02 weight review.

This script makes only public HNX/HSX report requests. It does not call
vnstock, use account quota, or write to PostgreSQL.
"""

from __future__ import annotations

import csv
import hashlib
import http.cookiejar
import json
import ssl
import time
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from decimal import Decimal
from html.parser import HTMLParser
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parent
CAPTURE = ROOT / "captures_20261102"
TRADE_DATE = "2019-01-02"
HNX_DATE = "02/01/2019"
UPCOM_SYMBOLS = [
    "BMS", "BSL", "BWS", "CBS", "CKA", "CLX", "DND", "DNL", "DNW",
    "DSP", "DVC", "FIC", "GTS", "HNF", "HSM", "L63", "LG9", "M10",
    "MGG", "MKP", "NAS", "NSG", "PVO", "SAS", "SGP", "TIS", "VTA",
]
HSX_PROBES = ["AFX", "PVP", "TCI"]

HNX_PAGE = "https://www.hnx.vn/vi-vn/co-phieu-etfs/du-lieu-thi-truong-uc.html"
HNX_ENDPOINT = "https://www.hnx.vn/ModuleReportStockETFs/Report_MD_PriceVolatilyti/ListData_UPCoM"
HSX_SWAGGER = "https://api.hsx.vn/mk/swagger/v1/swagger.json"
HSX_ENDPOINT = "https://api.hsx.vn/mk/api/v1/market/quote-report"


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def save_bytes(name: str, body: bytes) -> dict[str, Any]:
    path = CAPTURE / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(body)
    return {
        "file": name,
        "bytes": len(body),
        "sha256": sha256(body),
    }


class TableRows(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.rows: list[list[str]] = []
        self._row: list[str] | None = None
        self._cell: list[str] | None = None

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if tag == "tr":
            self._row = []
        elif tag in {"td", "th"} and self._row is not None:
            self._cell = []

    def handle_data(self, data: str) -> None:
        if self._cell is not None:
            self._cell.append(data)

    def handle_endtag(self, tag: str) -> None:
        if tag in {"td", "th"} and self._cell is not None and self._row is not None:
            self._row.append(" ".join("".join(self._cell).split()))
            self._cell = None
        elif tag == "tr" and self._row is not None:
            self.rows.append(self._row)
            self._row = None


def parse_hnx(body: bytes, symbol: str) -> tuple[list[str], list[str] | None]:
    parser = TableRows()
    parser.feed(body.decode("utf-8", "replace"))
    if not parser.rows:
        raise RuntimeError(f"HNX returned no table for {symbol}")
    headers = parser.rows[0]
    rows = [row for row in parser.rows[1:] if len(row) > 1 and row[1].upper() == symbol]
    if len(rows) > 1:
        raise RuntimeError(f"HNX returned duplicate exact-date rows for {symbol}")
    if rows and len(rows[0]) != len(headers):
        raise RuntimeError(f"HNX row/header width mismatch for {symbol}")
    return headers, rows[0] if rows else None


def request_bytes(
    opener: urllib.request.OpenerDirector,
    url: str,
    *,
    method: str = "GET",
    body: bytes | None = None,
    headers: dict[str, str] | None = None,
) -> tuple[int, dict[str, str], bytes]:
    req = urllib.request.Request(
        url,
        data=body,
        headers=headers or {},
        method=method,
    )
    with opener.open(req, timeout=30) as response:
        return response.status, dict(response.headers.items()), response.read()


def capture_hnx(opener: urllib.request.OpenerDirector) -> tuple[dict[str, Any], list[dict[str, str]]]:
    page_status, page_headers, page_body = request_bytes(
        opener,
        HNX_PAGE,
        headers={"User-Agent": "Mozilla/5.0", "Accept": "text/html,*/*"},
    )
    if page_status != 200:
        raise RuntimeError(f"HNX report page returned HTTP {page_status}")
    page_artifact = save_bytes("hnx_report_page.html", page_body)
    manifest: dict[str, Any] = {
        "page_url": HNX_PAGE,
        "page_http_status": page_status,
        "page_content_type": page_headers.get("Content-Type"),
        **page_artifact,
        "endpoint": HNX_ENDPOINT,
        "request_method": "POST",
        "request_fields_template": {
            "p_keysearch": "02/01/2019|0|0|'SYMBOL'|-1|02/01/2019|",
            "pCurrentPage": "1",
            "pRecordOnPage": "200",
            "pIsSearch": "1",
        },
        "responses": [],
    }
    summaries: list[dict[str, str]] = []
    for index, symbol in enumerate(UPCOM_SYMBOLS):
        fields = {
            "p_keysearch": f"{HNX_DATE}|0|0|'{symbol}'|-1|{HNX_DATE}|",
            "pCurrentPage": "1",
            "pRecordOnPage": "200",
            "pIsSearch": "1",
        }
        encoded = urllib.parse.urlencode(fields).encode("ascii")
        status, headers, body = request_bytes(
            opener,
            HNX_ENDPOINT,
            method="POST",
            body=encoded,
            headers={
                "User-Agent": "Mozilla/5.0",
                "Accept": "application/json, text/javascript, */*; q=0.01",
                "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8",
                "Origin": "https://www.hnx.vn",
                "Referer": HNX_PAGE,
                "X-Requested-With": "XMLHttpRequest",
            },
        )
        if status != 200:
            raise RuntimeError(f"HNX report returned HTTP {status} for {symbol}")
        name = f"hnx_upcom_{symbol}_20190102.html"
        artifact = save_bytes(name, body)
        headers_row, row = parse_hnx(body, symbol)
        manifest["responses"].append({
            "symbol": symbol,
            "http_status": status,
            "content_type": headers.get("Content-Type"),
            "request_fields": fields,
            "response_file": artifact["file"],
            "response_bytes": artifact["bytes"],
            "response_sha256": artifact["sha256"],
            "matching_rows": 1 if row else 0,
            "headers": headers_row,
            "row": row,
        })
        if row:
            summaries.append({
                "symbol": symbol,
                "reference": row[3],
                "ceiling": row[4],
                "floor": row[5],
                "open": row[6],
                "close": row[7],
                "average": row[8],
                "high": row[9],
                "low": row[10],
            })
        if index + 1 < len(UPCOM_SYMBOLS):
            time.sleep(0.6)
    return manifest, summaries


def capture_hsx(opener: urllib.request.OpenerDirector) -> dict[str, Any]:
    status, headers, swagger = request_bytes(
        opener,
        HSX_SWAGGER,
        headers={"User-Agent": "Mozilla/5.0", "Accept": "application/json"},
    )
    if status != 200:
        raise RuntimeError(f"HSX Swagger returned HTTP {status}")
    swagger_artifact = save_bytes("hsx_swagger.json", swagger)
    swagger_json = json.loads(swagger)
    operation = swagger_json["paths"]["/api/v1.0/market/quote-report"]["post"]
    route = {
        "method": "POST",
        "path": "/api/v1.0/market/quote-report",
        "parameters": operation.get("parameters", []),
    }
    result: dict[str, Any] = {
        "swagger_url": HSX_SWAGGER,
        "swagger_http_status": status,
        "swagger_content_type": headers.get("Content-Type"),
        "swagger_file": swagger_artifact["file"],
        "swagger_bytes": swagger_artifact["bytes"],
        "swagger_sha256": swagger_artifact["sha256"],
        "swagger_route": route,
        "endpoint": HSX_ENDPOINT,
        "date": TRADE_DATE,
        "responses": [],
    }
    for trading_by in ["VNUTI", *HSX_PROBES]:
        query = urllib.parse.urlencode({"tradingBy": trading_by, "date": TRADE_DATE})
        url = f"{HSX_ENDPOINT}?{query}"
        response_status, response_headers, body = request_bytes(
            opener,
            url,
            method="POST",
            body=b"{}",
            headers={
                "User-Agent": "Mozilla/5.0",
                "Accept": "application/json",
                "Content-Type": "application/json",
                "Origin": "https://www.hsx.vn",
                "Referer": "https://www.hsx.vn/",
            },
        )
        if response_status != 200:
            raise RuntimeError(f"HSX quote report returned HTTP {response_status} for {trading_by}")
        name = f"hsx_quote_report_{trading_by}_20190102.json"
        artifact = save_bytes(name, body)
        payload = json.loads(body)
        rows = payload.get("data", [])
        result["responses"].append({
            "tradingBy": trading_by,
            "url": url,
            "http_status": response_status,
            "content_type": response_headers.get("Content-Type"),
            "response_file": artifact["file"],
            "response_bytes": artifact["bytes"],
            "response_sha256": artifact["sha256"],
            "row_count": len(rows),
            "khp_rows": [row for row in rows if row.get("securitySymbol") == "KHP"],
        })
    return result


def capture_bsc_comparison(hnx_summaries: list[dict[str, str]]) -> dict[str, Any]:
    source_path = ROOT.parent / "bsc_price_limits_20190102" / "quarantine.jsonl"
    source_bytes = source_path.read_bytes()
    bsc_by_symbol: dict[str, list[str]] = {}
    for line in source_bytes.decode("utf-8").splitlines():
        item = json.loads(line)
        symbol = item["symbol"]
        if symbol not in UPCOM_SYMBOLS:
            continue
        response = item.get("source_response", {}).get("data", {})
        body = response.get("html", "") if isinstance(response, dict) else ""
        parser = TableRows()
        parser.feed(body)
        rows = [row for row in parser.rows if row and row[0].startswith("02/01/2019")]
        if len(rows) != 1 or len(rows[0]) < 10:
            raise RuntimeError(f"BSC quarantine does not contain one parseable row for {symbol}")
        bsc_by_symbol[symbol] = rows[0]

    hnx_by_symbol = {row["symbol"]: row for row in hnx_summaries}
    if set(bsc_by_symbol) != set(UPCOM_SYMBOLS) or set(hnx_by_symbol) != set(UPCOM_SYMBOLS):
        raise RuntimeError("HNX/BSC comparison is missing one or more UPCoM residual symbols")

    comparison_rows: list[dict[str, str]] = []
    for symbol in UPCOM_SYMBOLS:
        hnx = hnx_by_symbol[symbol]
        bsc = bsc_by_symbol[symbol]
        bsc_close = Decimal(bsc[1].replace(",", "")) / Decimal(1000)
        bsc_reference = Decimal(bsc[7].replace(",", "")) / Decimal(1000)
        bsc_ceiling = Decimal(bsc[8].replace(",", "")) / Decimal(1000)
        bsc_floor = Decimal(bsc[9].replace(",", "")) / Decimal(1000)
        comparison_rows.append({
            "symbol": symbol,
            "hnx_reference": hnx["reference"],
            "bsc_reference": str(bsc_reference),
            "reference_match": str(Decimal(hnx["reference"]) == bsc_reference).lower(),
            "hnx_ceiling": hnx["ceiling"],
            "bsc_ceiling": str(bsc_ceiling),
            "ceiling_match": str(Decimal(hnx["ceiling"]) == bsc_ceiling).lower(),
            "hnx_floor": hnx["floor"],
            "bsc_floor": str(bsc_floor),
            "floor_match": str(Decimal(hnx["floor"]) == bsc_floor).lower(),
            "hnx_close": hnx["close"],
            "bsc_close": str(bsc_close),
            "close_match": str(Decimal(hnx["close"]) == bsc_close).lower(),
            "bsc_matched_volume": bsc[3],
            "hnx_open": hnx["open"],
            "hnx_high": hnx["high"],
            "hnx_low": hnx["low"],
        })

    fields = list(comparison_rows[0])
    output_path = CAPTURE / "hnx_bsc_comparison_20190102.csv"
    with output_path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fields)
        writer.writeheader()
        writer.writerows(comparison_rows)
    matches = {
        column: sum(row[column] == "true" for row in comparison_rows)
        for column in ("reference_match", "ceiling_match", "floor_match", "close_match")
    }
    return {
        "bsc_input_file": str(source_path.relative_to(ROOT.parent.parent)).replace("\\", "/"),
        "bsc_input_bytes": len(source_bytes),
        "bsc_input_sha256": sha256(source_bytes),
        "comparison_file": output_path.name,
        "comparison_sha256": sha256(output_path.read_bytes()),
        "rows": len(comparison_rows),
        "matches": matches,
        "bsc_zero_matched_volume_rows": sum(Decimal(row["bsc_matched_volume"].replace(",", "")) == 0 for row in comparison_rows),
        "bsc_positive_matched_volume_rows": sum(Decimal(row["bsc_matched_volume"].replace(",", "")) > 0 for row in comparison_rows),
        "hnx_rows_without_open_high_low": sum(
            row["hnx_open"] == "-" and row["hnx_high"] == "-" and row["hnx_low"] == "-"
            for row in comparison_rows
        ),
    }


def main() -> None:
    CAPTURE.mkdir(parents=True, exist_ok=True)
    opener = urllib.request.build_opener(
        urllib.request.HTTPSHandler(context=ssl.create_default_context()),
        urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()),
    )
    hnx_manifest, summaries = capture_hnx(opener)
    hsx_manifest = capture_hsx(opener)
    comparison_manifest = capture_bsc_comparison(summaries)
    with (CAPTURE / "hnx_upcom_price_rows_20190102.csv").open("w", newline="", encoding="utf-8") as f:
        fields = ["symbol", "reference", "ceiling", "floor", "open", "close", "average", "high", "low"]
        writer = csv.DictWriter(f, fieldnames=fields)
        writer.writeheader()
        writer.writerows(summaries)
    manifest = {
        "captured_at_utc": datetime.now(timezone.utc).isoformat(),
        "date": TRADE_DATE,
        "tls_certificate_validation": "enabled",
        "vnstock_calls": 0,
        "database_writes": 0,
        "hnx": hnx_manifest,
        "hsx": hsx_manifest,
        "hnx_bsc_comparison": comparison_manifest,
    }
    manifest_path = CAPTURE / "capture_manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"CAPTURE {manifest_path}")
    print(f"HNX_ROWS {len(summaries)}/{len(UPCOM_SYMBOLS)}")
    print("HSX_ROWS", [(row["tradingBy"], row["row_count"]) for row in hsx_manifest["responses"]])


if __name__ == "__main__":
    main()
