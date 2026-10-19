#!/usr/bin/env python3
"""Validate close/range conflicts and generate their evidence-backed resolution."""

from __future__ import annotations

import csv
import hashlib
import json
from decimal import Decimal
from pathlib import Path


ROOT = Path(__file__).resolve().parent
PHASE2 = ROOT.parent
RAW_FILE = ROOT / "vndirect-violations.csv"
CAFEF_FILE = ROOT / "cafef-close-range-crosscheck.csv"
EXISTING_FILE = PHASE2 / "vndirect-model-bar-overrides.csv"
CORRECTIONS_FILE = ROOT / "vndirect-close-tick-corrections.csv"
DISPOSITION_FILE = ROOT / "vndirect-close-conflict-disposition.csv"
MIGRATION_FILE = ROOT.parents[3] / "sql" / "migrations" / "033_vndirect_close_tick_price_corrections.sql"
FIXTURE_FILE = ROOT.parents[3] / "tests" / "sql" / "vndirect_close_tick_fixture.sql"
TICK_RULES_URL = (
    "https://support.vndirect.com.vn/hc/vi/articles/"
    "360002192174-Quy-%C4%91%E1%BB%8Bnh-giao-d%E1%BB%8Bch-t%E1%BA%A1i-s%C3%A0n-HSX"
)

EXPECTED_NEW = {
    ("ILB", "2025-08-27"), ("DBT", "2025-09-18"),
    ("ELC", "2025-10-16"), ("NLG", "2025-10-16"),
    ("LGC", "2025-10-17"), ("LCG", "2025-10-27"),
    ("CRV", "2025-12-04"), ("CCC", "2025-12-23"),
    ("TVS", "2025-12-31"), ("VIX", "2026-03-05"),
    ("GEE", "2026-03-18"), ("CCI", "2026-03-26"),
    ("CTD", "2026-04-16"), ("HSG", "2026-04-29"),
    ("BMP", "2026-05-18"), ("HPG", "2026-05-22"),
    ("TCM", "2026-05-22"), ("TAL", "2026-05-26"),
    ("PAN", "2026-05-28"), ("GDT", "2026-06-16"),
}


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open(encoding="utf-8-sig", newline="") as stream:
        return list(csv.DictReader(stream))


def write_csv(path: Path, rows: list[dict[str, str]]) -> None:
    if not rows:
        raise ValueError(f"refusing to write empty evidence file: {path}")
    with path.open("w", encoding="utf-8-sig", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def tick_size(price: Decimal) -> Decimal:
    # Prices in these CSVs are in thousand VND.
    if price < Decimal("10"):
        return Decimal("0.01")
    if price < Decimal("50"):
        return Decimal("0.05")
    return Decimal("0.1")


def on_tick(price: Decimal) -> bool:
    step = tick_size(price)
    return price % step == 0


def sql_text(value: str) -> str:
    return "'" + value.replace("'", "''") + "'"


def decimal_sql(value: str) -> str:
    return format(Decimal(value), "f") + "::double precision"


def make_migration(corrections: list[dict[str, str]]) -> str:
    values = []
    expected_keys = []
    for row in corrections:
        ticker = row["ticker"]
        day = row["trade_date"]
        expected_keys.append(f"({sql_text(ticker)}, DATE '{day}')")
        values.append(
            "    ("
            + ", ".join([
                sql_text(ticker), f"DATE '{day}'",
                decimal_sql(row["vndirect_o"]), decimal_sql(row["vndirect_h"]),
                decimal_sql(row["vndirect_l"]), decimal_sql(row["cafef_c"]),
                decimal_sql(row["vndirect_c"]), row["vndirect_volume"],
                sql_text(row["cafef_request_url"]),
                sql_text(row["cafef_response_sha256"]),
                sql_text(row["secondary_evidence_url"]), sql_text(row["evidence_note"]),
            ]) + ")"
        )

    keys_sql = ",\n        ".join(expected_keys)
    return """-- Evidence-backed close corrections for traded HOSE bars.
-- VNDIRECT raw rows remain immutable; the model-price view uses CafeF close.
BEGIN;

WITH overrides(ticker,trade_date,model_o,model_h,model_l,model_c,
               source_close,source_volume,evidence_url,evidence_sha256,
               secondary_evidence_url,evidence_note) AS (
VALUES
""" + ",\n".join(values) + """
)
INSERT INTO core.vndirect_model_bar_overrides
    (symbol_id,trade_date,source,model_o,model_h,model_l,model_c,
     evidence_url,evidence_sha256,secondary_evidence_url,
     secondary_evidence_sha256,evidence_note)
SELECT s.symbol_id,o.trade_date,'vndirect',o.model_o,o.model_h,o.model_l,o.model_c,
       o.evidence_url,o.evidence_sha256,o.secondary_evidence_url,NULL,
       o.evidence_note
FROM overrides o
JOIN core.symbols s ON s.symbol=o.ticker
JOIN core.bars_daily_sources b
  ON b.symbol_id=s.symbol_id AND b.trade_date=o.trade_date AND b.source='vndirect'
 AND b.exchange_code='HOSE' AND b.is_traded AND b.v=o.source_volume
 AND b.o=o.model_o AND b.h=o.model_h AND b.l=o.model_l AND b.c=o.source_close
ON CONFLICT (symbol_id,trade_date,source) DO UPDATE
SET model_o=EXCLUDED.model_o,model_h=EXCLUDED.model_h,
    model_l=EXCLUDED.model_l,model_c=EXCLUDED.model_c,
    evidence_url=EXCLUDED.evidence_url,evidence_sha256=EXCLUDED.evidence_sha256,
    secondary_evidence_url=EXCLUDED.secondary_evidence_url,
    secondary_evidence_sha256=EXCLUDED.secondary_evidence_sha256,
    evidence_note=EXCLUDED.evidence_note;

DO $$
DECLARE resolved integer;
BEGIN
    SELECT count(*) INTO resolved
    FROM core.vndirect_model_bar_overrides m
    JOIN core.symbols s USING (symbol_id)
    WHERE m.source='vndirect'
      AND (s.symbol,m.trade_date) IN (
        """ + keys_sql + """
      );
    IF resolved <> 20 THEN
        RAISE EXCEPTION 'expected 20 close-tick model corrections; found %', resolved;
    END IF;
END $$;

COMMIT;
"""


def make_test_fixture(corrections: list[dict[str, str]]) -> str:
    ingest_id = "4a555b3f-3d56-4e99-91ae-aab1d9010333"
    payload = {
        "fixture": "synthetic CI-only rows for migration 033; never market/training data",
        "data": [
            {
                "code": row["ticker"], "date": row["trade_date"],
                "open": float(row["vndirect_o"]), "high": float(row["vndirect_h"]),
                "low": float(row["vndirect_l"]), "close": float(row["vndirect_c"]),
                "basicPrice": float(row["vndirect_c"]), "average": float(row["vndirect_c"]),
                "floor": "HOSE", "volume": int(row["vndirect_volume"]),
            }
            for row in corrections
        ],
    }
    payload_bytes = json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    payload_sha256 = hashlib.sha256(payload_bytes).hexdigest()
    payload_rows = []
    symbol_rows = []
    for index, row in enumerate(corrections):
        ticker, day = row["ticker"], row["trade_date"]
        payload_rows.append(
            "    (" + ", ".join([
                sql_text(ticker), f"DATE '{day}'",
                decimal_sql(row["vndirect_o"]), decimal_sql(row["vndirect_h"]),
                decimal_sql(row["vndirect_l"]), decimal_sql(row["vndirect_c"]),
                row["vndirect_volume"], str(index),
            ]) + ")"
        )
        symbol_rows.append(
            f"    ({sql_text(ticker)}, 'HOSE', TIMESTAMPTZ '{day} 00:00:00+07', "
            f"TIMESTAMPTZ '{day} 00:00:00+07')"
        )

    return """-- Synthetic CI-only fixture rows for migration 033; never production/training data.
BEGIN;

INSERT INTO core.symbols(symbol,exchange,first_seen_at,last_seen_at)
VALUES
""" + ",\n".join(symbol_rows) + """
ON CONFLICT (symbol) DO NOTHING;

WITH landing AS (
    INSERT INTO raw.landings
        (ingest_id,source,route,fetched_at,symbol,payload,payload_sha256,payload_bytes)
    VALUES
        ('""" + ingest_id + """'::uuid,'vndirect','equity_ohlcv',
         TIMESTAMPTZ '2026-10-19 10:00:00+07','CI_CLOSE_TICK_FIXTURE',
         '""" + sql_text(payload_bytes.decode("utf-8"))[1:-1] + """'::jsonb,
         '""" + payload_sha256 + """',decode('""" + payload_bytes.hex() + """','hex'))
    RETURNING landing_id,ingest_id,fetched_at
), bars(ticker,trade_date,o,h,l,c,v,source_row) AS (
VALUES
""" + ",\n".join(payload_rows) + """
)
INSERT INTO core.bars_daily_sources
    (symbol_id,trade_date,source,exchange_code,o,h,l,c,v,basic_price,average_price,adj_basis,is_traded,
     landing_id,source_row,ingest_id,fetched_at)
SELECT s.symbol_id,b.trade_date,'vndirect','HOSE',b.o,b.h,b.l,b.c,b.v,b.c,b.c,'unadjusted',true,
       l.landing_id,b.source_row,l.ingest_id,l.fetched_at
FROM bars b
JOIN core.symbols s ON s.symbol=b.ticker
CROSS JOIN landing l
ON CONFLICT (symbol_id,trade_date,source) DO NOTHING;

COMMIT;
"""


def main() -> int:
    raw_rows = read_csv(RAW_FILE)
    cafef_rows = read_csv(CAFEF_FILE)
    old_rows = read_csv(EXISTING_FILE)
    raw = {(r["symbol"], r["trade_date"]): r for r in raw_rows}
    cafef = {(r["symbol"], r["trade_date"]): r for r in cafef_rows}
    old_keys = {(r["ticker"], r["trade_date"]) for r in old_rows}

    conflicts = []
    for key, source in raw.items():
        close, low, high = map(Decimal, (source["c"], source["l"], source["h"]))
        if close < low or close > high:
            conflicts.append((key, source, cafef.get(key)))
    if len(conflicts) != 33:
        raise ValueError(f"expected 33 raw close/range conflicts; found {len(conflicts)}")

    target_rows = []
    dispositions = []
    for (ticker, day), source, public in sorted(conflicts):
        volume = int(source["v"])
        base = {
            "ticker": ticker, "trade_date": day,
            "exchange_code": source["exchange_code"], "vndirect_volume": source["v"],
            "vndirect_close": source["c"],
            "vndirect_close_outside_hl": "true",
            "cafef_close": public["cafef_c"] if public else "",
            "cafef_status": public["cafef_status"] if public else "NO_EXACT_DATE",
            "cafef_matched_volume": public["cafef_matched_volume"] if public else "",
            "cafef_request_url": public["cafef_request_url"] if public else "",
            "cafef_response_sha256": public["cafef_response_sha256"] if public else "",
            "cafef_archive_location": public["cafef_archive_location"] if public else "",
        }
        if volume == 0:
            if source["is_traded"] != "f":
                raise ValueError(f"zero-volume row is marked traded: {ticker} {day}")
            decision = "RETAIN_ZERO_VOLUME_NO_MATCHED_TRADE"
            reason = "Preserve the source observation; v=0 and is_traded=false mean the close is not an executed trade price. Do not synthesize a matched close."
        elif (ticker, day) in old_keys:
            decision = "CORRECTED_EXISTING_ACTION_MODEL_PRICE"
            reason = "Already covered by the earlier VSDC/CafeF evidence-backed model OHLC correction; no additional override required."
        else:
            decision = "CORRECT_CLOSE_FROM_CAFEF"
            reason = "Apply CafeF's same-session close to model OHLC only; preserve raw VNDIRECT source fields and lineage."
        dispositions.append({**base, "decision": decision, "disposition_note": reason})

    for key, source, public in conflicts:
        if int(source["v"]) <= 0 or key in old_keys:
            continue
        if public is None or public["cafef_status"] != "MATCHED":
            raise ValueError(f"missing same-session CafeF evidence: {key}")
        if source["exchange_code"] != "HOSE" or source["is_traded"] != "t":
            raise ValueError(f"unexpected venue/trade state for correction: {key}")
        if any(source[field] != public[f"cafef_{field}"] for field in ("o", "h", "l")):
            raise ValueError(f"CafeF OH fields do not exactly confirm VNDIRECT: {key}")
        if source["v"] != public["cafef_matched_volume"]:
            raise ValueError(f"CafeF matched volume does not match VNDIRECT: {key}")
        if not public["cafef_request_url"] or len(public["cafef_response_sha256"]) != 64:
            raise ValueError(f"missing reproducible CafeF evidence pointer: {key}")

        source_close = Decimal(source["c"])
        public_close = Decimal(public["cafef_c"])
        low, high = Decimal(source["l"]), Decimal(source["h"])
        if low <= source_close <= high:
            raise ValueError(f"VNDIRECT close is not outside its matched-price range: {key}")
        if not (low <= public_close <= high):
            raise ValueError(f"CafeF close is outside the confirmed shared range: {key}")
        if on_tick(source_close):
            raise ValueError(f"VNDIRECT close unexpectedly satisfies HOSE tick: {key}")
        if not on_tick(public_close):
            raise ValueError(f"CafeF close does not satisfy HOSE tick: {key}")

        source_close_text = source["c"]
        public_close_text = public["cafef_c"]
        note = (
            f"CafeF same-session raw OHLC and matched volume confirm VNDIRECT open/high/low "
            f"and volume; VNDIRECT close {source_close_text} is outside the shared high/low "
            f"range and off the HOSE tick increment, while CafeF close {public_close_text} "
            f"is inside the range and on-tick. Replace model close only; retain all raw "
            f"VNDIRECT OHLCV, trade status, landing, and row lineage."
        )
        target_rows.append({
            "ticker": key[0], "trade_date": key[1], "exchange_code": source["exchange_code"],
            "vndirect_o": source["o"], "vndirect_h": source["h"],
            "vndirect_l": source["l"], "vndirect_c": source["c"],
            "vndirect_volume": source["v"], "cafef_o": public["cafef_o"],
            "cafef_h": public["cafef_h"], "cafef_l": public["cafef_l"],
            "cafef_c": public["cafef_c"], "cafef_matched_volume": public["cafef_matched_volume"],
            "hose_tick_size_thousand_vnd": format(tick_size(public_close), "f"),
            "vndirect_close_on_tick": "false", "cafef_close_on_tick": "true",
            "cafef_request_url": public["cafef_request_url"],
            "cafef_response_sha256": public["cafef_response_sha256"],
            "cafef_archive_location": public["cafef_archive_location"],
            "secondary_evidence_url": TICK_RULES_URL,
            "evidence_note": note,
        })

    target_keys = {(r["ticker"], r["trade_date"]) for r in target_rows}
    if target_keys != EXPECTED_NEW:
        missing = sorted(EXPECTED_NEW - target_keys)
        extra = sorted(target_keys - EXPECTED_NEW)
        raise ValueError(f"new correction set changed; missing={missing}, extra={extra}")
    if len([r for r in dispositions if r["decision"] == "RETAIN_ZERO_VOLUME_NO_MATCHED_TRADE"]) != 8:
        raise ValueError("expected eight zero-volume close conflicts")
    if len([r for r in dispositions if r["decision"] == "CORRECTED_EXISTING_ACTION_MODEL_PRICE"]) != 5:
        raise ValueError("expected five previously corrected action bars")

    write_csv(CORRECTIONS_FILE, target_rows)
    write_csv(DISPOSITION_FILE, dispositions)
    MIGRATION_FILE.write_text(make_migration(target_rows), encoding="utf-8")
    FIXTURE_FILE.write_text(make_test_fixture(target_rows), encoding="utf-8")
    print("raw_close_conflicts=33 existing_action_corrections=5 new_close_corrections=20 zero_volume_retained=8")
    print(f"wrote {CORRECTIONS_FILE}")
    print(f"wrote {DISPOSITION_FILE}")
    print(f"wrote {MIGRATION_FILE}")
    print(f"wrote synthetic test fixture {FIXTURE_FILE}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
