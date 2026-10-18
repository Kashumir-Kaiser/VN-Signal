"""Validate archived reports and build an import manifest without refetching."""
from __future__ import annotations

import base64
import csv
import hashlib
from pathlib import Path

from fetch_sample import RAW, URL, TableRows, to_int


ROOT = Path(__file__).resolve().parent
RESULTS = ROOT / "sample-results.csv"
OUTPUT = ROOT / "sample-evidence-import.csv"


def main() -> None:
    import_rows: list[dict[str, str | int]] = []
    with RESULTS.open(encoding="utf-8-sig", newline="") as stream:
        results = list(csv.DictReader(stream))

    for result in results:
        if result["http_status"] != "200" or result["record_count_for_symbol"] != "1":
            raise SystemExit(f"{result['symbol']}: report was not one HTTP 200 symbol row")
        raw_path = ROOT / result["file"]
        payload = raw_path.read_bytes()
        digest = hashlib.sha256(payload).hexdigest()
        if digest != result["payload_sha256"]:
            raise SystemExit(f"{raw_path.name}: SHA-256 mismatch")
        parser = TableRows()
        parser.feed(payload.decode("utf-8", errors="strict"))
        matches = [
            row
            for row in parser.rows
            if len(row) >= 19 and row[1] == result["symbol"]
        ]
        if len(matches) != 1:
            raise SystemExit(
                f"{raw_path.name}: expected one matching report row, found {len(matches)}"
            )
        row = matches[0]
        matched_volume = to_int(row[17])
        matched_value = to_int(row[18])
        if matched_volume != 0 or matched_value != 0:
            raise SystemExit(f"{raw_path.name}: expected zero matched total")
        import_rows.append(
            {
                "symbol": result["symbol"],
                "market": "UPCOM",
                "trade_date": result["trade_date"],
                "source_row": to_int(row[0]) - 1,
                "buy_order_count": to_int(row[3]),
                "buy_order_volume": to_int(row[4]),
                "sell_order_count": to_int(row[6]),
                "sell_order_volume": to_int(row[7]),
                "total_matched_volume": matched_volume,
                "total_matched_value_vnd": matched_value,
                "source_url": URL,
                "payload_sha256": digest,
                "payload_base64": base64.b64encode(payload).decode("ascii"),
            }
        )

    fields = list(import_rows[0])
    with OUTPUT.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=fields)
        writer.writeheader()
        writer.writerows(import_rows)
    print(f"Validated {len(import_rows)} archived zero-match reports")


if __name__ == "__main__":
    main()
