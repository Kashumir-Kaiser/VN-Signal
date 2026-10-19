from __future__ import annotations

import csv
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parent
AUDIT = ROOT / "reference-snapshot-audit.csv"
NOTICE_INDEX = ROOT / "vsdc-event-notice-index.csv"
VSDC_CALENDAR = ROOT / "vsdc-candidate-calendar.csv"
VSDC_FETCHES = ROOT / "vsdc-candidate-fetches.csv"
COPHIEU_CALC = ROOT / "cophieu68-action-calculation-index.csv"
COPHIEU_FETCHES = ROOT / "cophieu68-event-fetches.csv"
CAFEF_BARS = ROOT / "cafef-candidate-bars.csv"
FACTOR_OUTPUT = ROOT / "reference-factor-resolution-ledger.csv"
BAR_OUTPUT = ROOT / "vndirect-model-bar-overrides.csv"
MIGRATION_OUTPUT = ROOT.parent.parent.parent / "sql" / "migrations" / "032_vndirect_reference_factor_resolution.sql"

# Values are in thousand VND. These are the terms in the VSDC corporate-action
# notices; stock percentages are new shares per old share and rights are new
# shares per old share at the stated subscription price.
ACTION_TERMS: dict[tuple[str, str], tuple[float, float, float, float]] = {
    ("HPX", "2018-12-20"): (0, .1594, 0, 0),
    ("GMC", "2019-12-02"): (0, 0, .5, 15),
    ("TMS", "2019-12-04"): (1, 0, 0, 0),
    ("SJE", "2020-09-09"): (1, .20, 0, 0),
    ("EVG", "2021-01-15"): (0, 0, .75, 10),
    ("BAX", "2021-04-23"): (13.093, 0, 0, 0),
    ("VNC", "2021-04-23"): (1, 0, 0, 0),
    ("HEC", "2021-06-04"): (4, 0, 0, 0),
    ("KKC", "2021-06-04"): (1, 0, 0, 0),
    ("SIV", "2021-06-04"): (1.4, 0, 0, 0),
    ("CH5", "2021-06-07"): (1.3, 0, 0, 0),
    ("TV4", "2021-10-06"): (0, .12, 0, 0),
    ("CTS", "2022-08-24"): (0, .2942, 0, 0),
    ("HBC", "2022-08-24"): (.3, .07, 0, 0),
    ("C32", "2022-08-25"): (1.2, 0, 0, 0),
    ("SGN", "2022-08-26"): (2.5, 0, 0, 0),
    ("SHI", "2022-08-26"): (0, .08, 0, 0),
    ("VIX", "2022-08-26"): (0, .06, 0, 0),
    ("TBC", "2022-08-29"): (1.5, 0, 0, 0),
    ("TCL", "2022-08-29"): (4.2, 0, 0, 0),
    ("ADS", "2022-09-05"): (0, .15, 0, 0),
    ("VPI", "2022-09-08"): (0, .10, 0, 0),
    ("GIL", "2022-09-09"): (0, .15, 0, 0),
    ("SGR", "2022-09-09"): (.5, 0, 0, 0),
    ("CMG", "2022-09-12"): (0, .3762, 0, 0),
    ("SZL", "2022-09-12"): (4, 0, 0, 0),
    ("DBT", "2023-01-30"): (0, .10, 0, 0),
    ("PVT", "2024-04-11"): (0, .10, 0, 0),
    ("LSS", "2024-04-16"): (0, .075, 0, 0),
    ("VIB", "2024-04-17"): (.65, 0, 0, 0),
    ("VPD", "2024-04-23"): (1, 0, 0, 0),
    ("HDC", "2024-04-26"): (0, 0, .148, 15),
    ("TCI", "2024-05-10"): (0, .145, 0, 0),
    ("GDA", "2025-05-12"): (1, 0, 0, 0),
    ("QCC", "2025-05-12"): (.5, 0, 0, 0),
    ("TPS", "2025-05-12"): (2.5, 0, 0, 0),
    ("FMC", "2025-05-14"): (2, 0, 0, 0),
    ("FTS", "2025-05-14"): (.5, .10, 0, 0),
    ("GEX", "2025-05-14"): (0, .05, 0, 0),
    ("VNM", "2025-05-14"): (2, 0, 0, 0),
    ("VNS", "2025-05-14"): (1, 0, 0, 0),
    ("AAM", "2019-07-10"): (.5, 0, 0, 0),
}

# VNDIRECT's pre-event OHLC on these five bars already contains the upcoming
# event factor. CafeF's dated raw OHLC and the VSDC notices support these values.
MODEL_BAR_KEYS = {
    ("FMC", "2025-05-13"): ("2025-05-14", "https://vsdc.vn/vi/ad/182216"),
    ("FTS", "2025-05-13"): ("2025-05-14", "https://vsdc.vn/vi/ad/182403"),
    ("GEX", "2025-05-13"): ("2025-05-14", "https://vsdc.vn/vi/ad/182291"),
    ("VNM", "2025-05-13"): ("2025-05-14", "https://vsdc.vn/vi/ad/182377"),
    ("VNS", "2025-05-13"): ("2025-05-14", "https://vsdc.vn/vi/ad/182318"),
}
AAM_NOTICE = {
    "ticker": "AAM",
    "candidate_date": "2019-07-10",
    "notice_url": "https://vsdc.vn/vi/ad/57234",
    "calendar_title": "AAM: Tạm ứng cổ tức đợt 1 năm 2019 bằng tiền",
    "notice_sha256": "e02863de6a6c145492ae9bb6051e538bb81c93c3b650a12b95c3cfca458ea524",
}
VSDC_RIGHTS_RULE = "https://vsdc.vn/vi/ad/195688"
UPCOM_REFERENCE_RULE = "https://cbtd.hnx.vn/vi-vn/hoi-dap.html"


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open(encoding="utf-8-sig", newline="") as stream:
        return list(csv.DictReader(stream))


def write_csv(path: Path, fields: list[str], rows: list[dict[str, object]]) -> None:
    with path.open("w", encoding="utf-8-sig", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)


def sql_text(value: object) -> str:
    return "'" + str(value).replace("'", "''") + "'"


def write_migration(factors: list[dict[str, object]], bars: list[dict[str, object]]) -> None:
    factor_values = ",\n".join(
        "    (" + ", ".join([
            sql_text(row["ticker"]),
            f"DATE {sql_text(row['trade_date'])}",
            f"{row['reference_adjustment_ratio']}::double precision",
            sql_text(row["resolution_kind"]),
            sql_text(row["evidence_url"]),
            sql_text(row["evidence_sha256"]),
            sql_text(row["secondary_evidence_url"]),
            sql_text(row["secondary_evidence_sha256"]),
            sql_text(row["evidence_note"]),
        ]) + ")"
        for row in factors
    )
    bar_values = ",\n".join(
        "    (" + ", ".join([
            sql_text(row["ticker"]),
            f"DATE {sql_text(row['trade_date'])}",
            *[f"{row[k]}::double precision" for k in ("o", "h", "l", "c")],
            sql_text(row["evidence_url"]),
            sql_text(row["evidence_sha256"]),
            sql_text(row["secondary_evidence_url"]),
            sql_text(row["secondary_evidence_sha256"]),
            sql_text(row["evidence_note"]),
        ]) + ")"
        for row in bars
    )
    migration = f"""-- Resolve every audited VNDIRECT reference candidate and correct source bars
-- that already embed a future adjustment, without rewriting raw observations.
BEGIN;

WITH resolutions(ticker,trade_date,reference_adjustment_ratio,resolution_kind,
                 evidence_url,evidence_sha256,secondary_evidence_url,
                 secondary_evidence_sha256,evidence_note) AS (
VALUES
{factor_values}
)
INSERT INTO core.vndirect_reference_adjustment_overrides
    (symbol_id,trade_date,source,reference_adjustment_ratio,resolution_kind,
     evidence_url,evidence_sha256,secondary_evidence_url,
     secondary_evidence_sha256,evidence_note)
SELECT s.symbol_id,r.trade_date,'vndirect',r.reference_adjustment_ratio,r.resolution_kind,
       r.evidence_url,r.evidence_sha256,r.secondary_evidence_url,
       NULLIF(r.secondary_evidence_sha256,''),r.evidence_note
FROM resolutions r
JOIN core.symbols s ON s.symbol=r.ticker
JOIN core.bars_daily_sources b
  ON b.symbol_id=s.symbol_id AND b.trade_date=r.trade_date AND b.source='vndirect'
ON CONFLICT (symbol_id,trade_date,source) DO UPDATE
SET reference_adjustment_ratio=EXCLUDED.reference_adjustment_ratio,
    resolution_kind=EXCLUDED.resolution_kind,
    evidence_url=EXCLUDED.evidence_url,
    evidence_sha256=EXCLUDED.evidence_sha256,
    secondary_evidence_url=EXCLUDED.secondary_evidence_url,
    secondary_evidence_sha256=EXCLUDED.secondary_evidence_sha256,
    evidence_note=EXCLUDED.evidence_note;

WITH overrides(ticker,trade_date,model_o,model_h,model_l,model_c,
               evidence_url,evidence_sha256,secondary_evidence_url,
               secondary_evidence_sha256,evidence_note) AS (
VALUES
{bar_values}
)
INSERT INTO core.vndirect_model_bar_overrides
    (symbol_id,trade_date,source,model_o,model_h,model_l,model_c,
     evidence_url,evidence_sha256,secondary_evidence_url,
     secondary_evidence_sha256,evidence_note)
SELECT s.symbol_id,o.trade_date,'vndirect',o.model_o,o.model_h,o.model_l,o.model_c,
       o.evidence_url,o.evidence_sha256,o.secondary_evidence_url,
       NULLIF(o.secondary_evidence_sha256,''),o.evidence_note
FROM overrides o
JOIN core.symbols s ON s.symbol=o.ticker
JOIN core.bars_daily_sources b
  ON b.symbol_id=s.symbol_id AND b.trade_date=o.trade_date AND b.source='vndirect'
ON CONFLICT (symbol_id,trade_date,source) DO UPDATE
SET model_o=EXCLUDED.model_o,model_h=EXCLUDED.model_h,
    model_l=EXCLUDED.model_l,model_c=EXCLUDED.model_c,
    evidence_url=EXCLUDED.evidence_url,evidence_sha256=EXCLUDED.evidence_sha256,
    secondary_evidence_url=EXCLUDED.secondary_evidence_url,
    secondary_evidence_sha256=EXCLUDED.secondary_evidence_sha256,
    evidence_note=EXCLUDED.evidence_note;

COMMIT;
"""
    MIGRATION_OUTPUT.write_text(migration, encoding="utf-8", newline="\n")


def build() -> tuple[list[dict[str, object]], list[dict[str, object]]]:
    audit = read_csv(AUDIT)
    if len(audit) != 641:
        raise ValueError(f"expected the 641-row audited candidate set, found {len(audit)}")
    audit_by_key = {(r["ticker"], r["trade_date"]): r for r in audit}
    if len(audit_by_key) != len(audit):
        raise ValueError("reference-snapshot-audit.csv contains duplicate ticker/date rows")

    notice_rows = read_csv(NOTICE_INDEX)
    notice_by_key = {(r["ticker"], r["candidate_date"]): r for r in notice_rows}
    if len(notice_by_key) != 41:
        raise ValueError(f"expected 41 unique VSDC action pairs, found {len(notice_by_key)}")
    notice_by_key[('AAM', '2019-07-10')] = AAM_NOTICE
    if set(notice_by_key) != set(ACTION_TERMS):
        missing = sorted(set(ACTION_TERMS) - set(notice_by_key))
        extra = sorted(set(notice_by_key) - set(ACTION_TERMS))
        raise ValueError(f"official action list differs from terms: missing={missing}, extra={extra}")
    if not set(notice_by_key).issubset(audit_by_key):
        raise ValueError("an official corporate action is absent from the 641 candidate rows")

    vsdc_cal = read_csv(VSDC_CALENDAR)
    vsdc_fetch = {(r["ticker"], r["candidate_date"]): r for r in read_csv(VSDC_FETCHES)}
    cophieu_calc = {(r["ticker"], r["candidate_date"]): r for r in read_csv(COPHIEU_CALC)}
    cophieu_fetch = {r["ticker"]: r for r in read_csv(COPHIEU_FETCHES)}
    cafef_bars = read_csv(CAFEF_BARS)

    calendar_by_candidate: dict[tuple[str, str], list[dict[str, str]]] = {}
    for row in vsdc_cal:
        calendar_by_candidate.setdefault((row["candidate_ticker"], row["candidate_date"]), []).append(row)
    bars_by_candidate: dict[tuple[str, str], list[dict[str, str]]] = {}
    for row in cafef_bars:
        bars_by_candidate.setdefault((row["ticker"], row["candidate_date"]), []).append(row)

    corrections: list[dict[str, object]] = []
    corrected_prior_close: dict[tuple[str, str], float] = {}
    for (ticker, bar_date), (candidate_date, notice_url) in MODEL_BAR_KEYS.items():
        exact = [
            r for r in cafef_bars
            if r["ticker"] == ticker and r["candidate_date"] == candidate_date and r["bar_date"] == bar_date
        ]
        if len(exact) != 1:
            raise ValueError(f"expected one exact CafeF raw bar for {ticker} {bar_date}, got {len(exact)}")
        bar = exact[0]
        corrected_prior_close[(ticker, candidate_date)] = float(bar["close"])
        corrections.append({
            "ticker": ticker,
            "trade_date": bar_date,
            "action_date": candidate_date,
            "o": bar["open"],
            "h": bar["high"],
            "l": bar["low"],
            "c": bar["close"],
            "volume_source": "vndirect preserved",
            "evidence_url": bar["request_url"],
            "evidence_sha256": bar["response_sha256"],
            "secondary_evidence_url": notice_url,
            "secondary_evidence_sha256": notice_by_key[(ticker, candidate_date)].get("notice_sha256", ""),
            "evidence_note": (
                f"CafeF raw OHLC on {bar_date} precedes the VSDC-confirmed {candidate_date} ex-right session. "
                "VNDIRECT's source OHLC already equals the post-action reference on this pre-event bar. "
                "Replace only model OHLC; keep the VNDIRECT source row, volume, is_traded, and lineage intact."
            ),
        })

    factor_rows: list[dict[str, object]] = []
    for key in sorted(audit_by_key, key=lambda k: (k[1], k[0])):
        source = audit_by_key[key]
        ticker, candidate_date = key
        notice = notice_by_key.get(key)
        query = vsdc_fetch.get(key, {})
        calc = cophieu_calc.get(key, {})
        secondary = cophieu_fetch.get(ticker, {})
        baseline_source = float(source["reference_baseline"])
        baseline = corrected_prior_close.get(key, baseline_source)
        if ticker == "CH5" and candidate_date == "2021-06-07":
            # UPCoM reference uses the last actually traded VWAP, even though
            # the preceding exchange sessions carried a zero-volume reference.
            baseline = 15.0
        if baseline <= 0:
            raise ValueError(f"non-positive event baseline for {ticker} {candidate_date}")

        if notice is not None:
            cash, stock_ratio, rights_ratio, subscription = ACTION_TERMS[key]
            theoretical_reference = (baseline - cash + rights_ratio * subscription) / (1 + stock_ratio + rights_ratio)
            ratio = theoretical_reference / baseline
            if ratio <= 0 or abs(ratio - 1) < 1e-12:
                raise ValueError(f"invalid corporate-action factor for {ticker} {candidate_date}: {ratio}")
            evidence_url = notice.get("archived_url") or notice["notice_url"]
            evidence_sha = notice.get("notice_sha256", "")
            secondary_url = calc.get("event_calc_url") or ("https://cophieu68.vn/quote/event.php?id=" + ticker.lower())
            secondary_hash = calc.get("response_sha256") or secondary.get("sha256", "")
            if ticker == "AAM":
                evidence_url = AAM_NOTICE["notice_url"]
                evidence_sha = AAM_NOTICE["notice_sha256"]
            term_text = (
                f"cash={cash:g}, stock_ratio={stock_ratio:g}, rights_ratio={rights_ratio:g}, "
                f"subscription={subscription:g} thousand VND"
            )
            if key == ("CTS", "2022-08-24"):
                term_text += "; includes all three VSDC stock distributions: 21.96% + 3.73% + 3.73%"
            if key == ("CH5", "2021-06-07"):
                term_text += "; baseline is last traded UPCoM VWAP 15.0, carried across two zero-volume sessions"
            if key[0] in {"FMC", "FTS", "GEX", "VNM", "VNS"} and candidate_date == "2025-05-14":
                term_text += "; prior-session baseline corrected from CafeF raw OHLC"
            note = (
                f"CORPORATE_ACTION; theoretical ex-right reference={theoretical_reference:.12f} thousand VND; "
                f"baseline={baseline:.12f}; {term_text}; ratio=reference/baseline. "
                f"VSDC notice SHA-256={evidence_sha}. "
                "The factor is computed from the official action terms without exchange-tick rounding; raw bar prices remain auditable."
            )
            kind = "CORPORATE_ACTION"
            source_hash = evidence_sha
        else:
            ratio = 1.0
            evidence_url = "https://vsdc.vn/lich-thq/search"
            secondary_url = "https://cophieu68.vn/quote/event.php?id=" + ticker.lower()
            records = [r for r in calendar_by_candidate.get(key, []) if r["ticker"].upper() == ticker]
            record_summary = "; ".join(
                f"{r['record_date']} {r['title']} [{r['notice_url']}]" for r in records[:4]
            ) or "no same-symbol record in the queried 90-day window"
            fetch_hash = query.get("response_sha256", "")
            secondary_hash = secondary.get("sha256", "")
            note = (
                "NO_ACTION; candidate basicPrice/reference mismatch is not an ex-right factor on this session. "
                f"VSDC same-symbol calendar records: {record_summary}. "
                f"VSDC ticker/date search covered {candidate_date} through +90 calendar days; response SHA-256={fetch_hash}. "
                f"Cophieu symbol event page SHA-256={secondary_hash}. "
                "No corporate action is effective on this candidate session; factor=1 preserves every source bar, including zero-volume bars."
            )
            kind = "NO_ACTION"
            source_hash = fetch_hash
            secondary_hash = secondary.get("sha256", "")

        factor_rows.append({
            "ticker": ticker,
            "trade_date": candidate_date,
            "exchange_code": source["exchange_code"],
            "is_traded": source["is_traded"],
            "volume": source["v"],
            "source_close": source["c"],
            "source_basic_price": source["basic_price"],
            "source_reference_baseline": f"{baseline_source:.12f}",
            "resolved_reference_baseline": f"{baseline:.12f}",
            "resolved_reference_price": f"{baseline * ratio:.12f}",
            "model_factor_before": source["model_factor"],
            "snapshot_event_factor": source["snapshot_event_factor"],
            "reference_adjustment_ratio": f"{ratio:.15f}",
            "resolution_kind": kind,
            "evidence_url": evidence_url,
            "evidence_sha256": source_hash,
            "secondary_evidence_url": secondary_url,
            "secondary_evidence_sha256": secondary_hash,
            "evidence_note": note,
        })

    if len(factor_rows) != 641:
        raise ValueError(f"expected 641 factor resolutions, got {len(factor_rows)}")
    action_count = sum(r["resolution_kind"] == "CORPORATE_ACTION" for r in factor_rows)
    no_action_count = sum(r["resolution_kind"] == "NO_ACTION" for r in factor_rows)
    if action_count != 42 or no_action_count != 599:
        raise ValueError(f"expected 42 actions / 599 no-actions, found {action_count}/{no_action_count}")

    write_csv(FACTOR_OUTPUT, list(factor_rows[0]), factor_rows)
    write_csv(BAR_OUTPUT, list(corrections[0]), corrections)
    write_migration(factor_rows, corrections)
    return factor_rows, corrections


if __name__ == "__main__":
    factors, bars = build()
    print(f"factor resolutions={len(factors)}; corporate actions=42; no-action sessions=599; model OHLC overrides={len(bars)}")
    print(f"wrote {FACTOR_OUTPUT}, {BAR_OUTPUT}, and {MIGRATION_OUTPUT}")
