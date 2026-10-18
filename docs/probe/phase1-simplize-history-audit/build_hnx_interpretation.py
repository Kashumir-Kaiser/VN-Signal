"""Parse archived HNX activity columns into matched/deal interpretations."""

from __future__ import annotations

import csv
import hashlib
from pathlib import Path

from verify_hnx import TableRows, URL, to_int


ROOT = Path(__file__).resolve().parent
RESULTS = ROOT / "hnx-verification.csv"
OUTPUT = ROOT / "hnx-interpretation-import.csv"
EXPECTED = {
    "2026-01-29": (0, 0, 15100, 175160000),
    "2026-01-30": (0, 0, 4900, 56840000),
    "2026-02-12": (0, 0, 4900, 56840000),
}


def main() -> None:
    with RESULTS.open(encoding="utf-8-sig", newline="") as stream:
        results = list(csv.DictReader(stream))
    if len(results) != len(EXPECTED):
        raise SystemExit(f"expected {len(EXPECTED)} HNX rows, found {len(results)}")

    rows: list[dict[str, str | int]] = []
    verified_rows: list[dict[str, str | int]] = []
    for result in results:
        trade_date = result["trade_date"]
        if result["http_status"] != "200" or result["record_count_for_symbol"] != "1":
            raise SystemExit(f"{trade_date}: expected one HTTP 200 VNX row")
        payload = (ROOT / "hnx_raw" / result["file"]).read_bytes()
        digest = hashlib.sha256(payload).hexdigest()
        if digest != result["payload_sha256"]:
            raise SystemExit(f"{result['file']}: SHA-256 mismatch")

        parser = TableRows()
        parser.feed(payload.decode("utf-8", errors="strict"))
        matches = [row for row in parser.rows if len(row) >= 19 and row[1] == "VNX"]
        if len(matches) != 1:
            raise SystemExit(f"{result['file']}: expected one parsed VNX row, found {len(matches)}")
        report = matches[0]
        matched_volume = sum(to_int(report[i]) for i in (9, 11, 13))
        matched_value = sum(to_int(report[i]) for i in (10, 12, 14))
        negotiated_volume = to_int(report[15])
        negotiated_value = to_int(report[16])
        total_market_volume = to_int(report[17])
        total_market_value = to_int(report[18])
        actual = (matched_volume, matched_value, negotiated_volume, negotiated_value)
        if actual != EXPECTED[trade_date]:
            raise SystemExit(f"{trade_date}: unexpected matched/deal columns {actual}")
        if matched_volume + negotiated_volume != total_market_volume:
            raise SystemExit(f"{trade_date}: share volumes do not reconcile to total market")
        if matched_value + negotiated_value != total_market_value:
            raise SystemExit(f"{trade_date}: values do not reconcile to total market")

        verified_rows.append({
            "symbol": "VNX",
            "trade_date": trade_date,
            "report_route": result["report_route"],
            "http_status": result["http_status"],
            "record_count_for_symbol": result["record_count_for_symbol"],
            "buy_order_count": to_int(report[3]),
            "buy_order_volume": to_int(report[4]),
            "buy_order_value_vnd": to_int(report[5]),
            "sell_order_count": to_int(report[6]),
            "sell_order_volume": to_int(report[7]),
            "sell_order_value_vnd": to_int(report[8]),
            "continuous_matched_volume": to_int(report[9]),
            "continuous_matched_value_vnd": to_int(report[10]),
            "closing_auction_volume": to_int(report[11]),
            "closing_auction_value_vnd": to_int(report[12]),
            "after_hours_matched_volume": to_int(report[13]),
            "after_hours_matched_value_vnd": to_int(report[14]),
            "negotiated_volume": negotiated_volume,
            "negotiated_value_vnd": negotiated_value,
            "total_market_volume": total_market_volume,
            "total_market_value_vnd": total_market_value,
            "source_url": result["source_url"],
            "filter": result["filter"],
            "file": result["file"],
            "payload_sha256": digest,
        })

        rows.append({
            "symbol": "VNX",
            "market": "UPCOM",
            "trade_date": trade_date,
            "source_row": to_int(report[0]) - 1,
            "buy_order_count": to_int(report[3]),
            "buy_order_volume": to_int(report[4]),
            "sell_order_count": to_int(report[6]),
            "sell_order_volume": to_int(report[7]),
            "total_matched_volume": matched_volume,
            "total_matched_value_vnd": matched_value,
            "total_negotiated_volume": negotiated_volume,
            "total_negotiated_value_vnd": negotiated_value,
            "total_market_volume": total_market_volume,
            "total_market_value_vnd": total_market_value,
            "source_url": URL,
            "payload_sha256": digest,
        })

    with RESULTS.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(verified_rows[0]))
        writer.writeheader()
        writer.writerows(verified_rows)
    with OUTPUT.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
    print(f"Validated {len(rows)} HNX matched/deal interpretations")


if __name__ == "__main__":
    main()
