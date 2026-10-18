"""Retained first-pass parser; do not rebuild its mislabeled import manifest."""

from __future__ import annotations

import base64
import csv
import hashlib
from pathlib import Path

from verify_hnx import RAW, TableRows, URL, to_int


ROOT = Path(__file__).resolve().parent
RESULTS = ROOT / "hnx-verification.csv"
OUTPUT = ROOT / "hnx-evidence-import.csv"


def main() -> None:
    raise SystemExit(
        "Superseded: this first-pass parser treated HNX total-market columns as matched. "
        "Use build_hnx_interpretation.py and import_hnx_interpretations.sql."
    )

    with RESULTS.open(encoding="utf-8-sig", newline="") as stream:
        results = list(csv.DictReader(stream))
    if len(results) != 3:
        raise SystemExit(f"expected 3 HNX reports, found {len(results)}")

    import_rows: list[dict[str, str | int]] = []
    for result in results:
        if result["http_status"] != "200" or result["record_count_for_symbol"] != "1":
            raise SystemExit(f"{result['trade_date']}: expected one HTTP 200 VNX report row")
        payload = (ROOT / "hnx_raw" / result["file"]).read_bytes()
        digest = hashlib.sha256(payload).hexdigest()
        if digest != result["payload_sha256"]:
            raise SystemExit(f"{result['file']}: SHA-256 mismatch")

        parser = TableRows()
        parser.feed(payload.decode("utf-8", errors="strict"))
        matches = [row for row in parser.rows if len(row) >= 19 and row[1] == "VNX"]
        if len(matches) != 1:
            raise SystemExit(f"{result['file']}: expected one parsed VNX row, found {len(matches)}")
        row = matches[0]
        values = {
            "source_row": to_int(row[0]) - 1,
            "buy_order_count": to_int(row[3]),
            "buy_order_volume": to_int(row[4]),
            "sell_order_count": to_int(row[6]),
            "sell_order_volume": to_int(row[7]),
            "total_matched_volume": to_int(row[17]),
            "total_matched_value_vnd": to_int(row[18]),
        }
        if values["total_matched_volume"] <= 0 or values["total_matched_value_vnd"] <= 0:
            raise SystemExit(f"{result['file']}: HNX does not show a positive execution")
        if values["total_matched_volume"] != int(result["total_matched_volume"]):
            raise SystemExit(f"{result['file']}: summary differs from raw report")

        import_rows.append({
            "symbol": "VNX",
            "market": "UPCOM",
            "trade_date": result["trade_date"],
            **values,
            "source_url": URL,
            "payload_sha256": digest,
            "payload_base64": base64.b64encode(payload).decode("ascii"),
        })

    with OUTPUT.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(import_rows[0]))
        writer.writeheader()
        writer.writerows(import_rows)
    print(f"Validated {len(import_rows)} HNX positive-match reports")


if __name__ == "__main__":
    main()
