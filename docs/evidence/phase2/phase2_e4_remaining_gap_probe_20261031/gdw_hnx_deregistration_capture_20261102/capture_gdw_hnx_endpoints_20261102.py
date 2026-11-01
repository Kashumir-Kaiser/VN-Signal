#!/usr/bin/env python3
"""Capture GDW's official HNX UPCoM cessation and first-HNX notices."""

from __future__ import annotations

import csv
import hashlib
import json
import ssl
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import urlparse


OUT = Path(__file__).resolve().parent
CAPTURE_TIME_BASIS = "actual HTTP capture UTC recorded in source manifest"

SOURCES = [
    {
        "symbol": "GDW",
        "source": "hnx",
        "file": "hnx_gdw_deregistration_1385tb_sgdhn_2018-11-21.pdf",
        "url": "https://owa.hnx.vn/ftp/cims/2018/12_W2/000000007986358_1385tb_20181121_1.PDF",
        "expected_bytes": 213730,
        "expected_sha256": "0755fec1e2e91593f2e2506f6fe65e68d70f672c06b809d685a78f7bd799af00",
        "document_date": "2018-11-21",
        "last_trade_date": "2018-12-06",
        "prior_ceased_from": "2018-12-07",
        "first_trade_date": "",
        "notice_id": "1385/TB-SGDHN",
        "source_attribution": "Hanoi Stock Exchange official Notice 1385/TB-SGDHN, dated 2018-11-21.",
        "source_claim": (
            "The scanned HNX notice identifies GDW and states that its UPCoM "
            "registration cancellation is effective 2018-12-07 and its last "
            "trading day at HNX is 2018-12-06."
        ),
        "source_limitation": (
            "Establishes the final UPCoM session and cancellation-effective "
            "date only; it does not report matched volume or classify each "
            "intervening session, and does not establish the first HNX session."
        ),
    },
    {
        "symbol": "GDW",
        "source": "hnx",
        "file": "hnx_gdw_first_hnx_trade_1458tb_sgdhn_2018-12-06.pdf",
        "url": "https://owa.hnx.vn/ftp//PORTALNEW/HEADER_IMAGES/20181206/GDW_Ngay%20giao%20dich%20dau%20tien.pdf",
        "expected_bytes": 634641,
        "expected_sha256": "aeba54a3203a3baf7fb7c6e7ff7b7cedcd3bece591075e232a44c9769bb642e5",
        "document_date": "2018-12-06",
        "last_trade_date": "",
        "prior_ceased_from": "",
        "first_trade_date": "2018-12-18",
        "notice_id": "1458/TB-SGDHN",
        "source_attribution": "Hanoi Stock Exchange official Notice 1458/TB-SGDHN, dated 2018-12-06.",
        "source_claim": (
            "The scanned HNX notice identifies GDW and states its first HNX "
            "trading date as Tuesday 2018-12-18, with 9,500,000 listed shares."
        ),
        "source_limitation": (
            "Establishes the first HNX trading date and listed share count "
            "only; it does not establish the prior UPCoM endpoint or the "
            "status of any intervening session."
        ),
    },
]

LANDING_FIELDS = [
    "symbol",
    "source",
    "route",
    "fetched_at",
    "source_url",
    "local_file",
    "document_date",
    "last_trade_date",
    "prior_ceased_from",
    "first_trade_date",
    "payload_sha256",
    "payload_size",
    "media_type",
    "source_attribution",
    "source_claim",
    "source_limitation",
    "capture_time_basis",
    "metadata_json",
    "body_hex",
]


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="microseconds").replace("+00:00", "Z")


def main() -> None:
    context = ssl.create_default_context()
    manifest: dict[str, object] = {
        "schema_version": 1,
        "scope": "GDW official HNX UPCoM cessation and first-HNX endpoints",
        "tls_certificate_validation": "Python default SSL certificate validation; no bypass",
        "capture_time_basis": CAPTURE_TIME_BASIS,
        "captures": [],
        "limitations": [
            "The official 2018-12-06 UPCoM report captured separately reports zero matched volume; the notice proves the exchange's final session designation, not a matched trade.",
            "No per-session traded, no-trade, suspended, or delisted state is inferred for the gap between the two venue endpoints.",
        ],
    }
    landing_rows: list[dict[str, str | int]] = []

    for spec in SOURCES:
        started = utc_now()
        request = urllib.request.Request(
            spec["url"],
            headers={"User-Agent": "VN-Signal Phase 2 source evidence capture/1.0"},
        )
        with urllib.request.urlopen(request, context=context, timeout=45) as response:
            status = response.status
            final_url = response.geturl()
            content_type = response.headers.get_content_type()
            body = response.read()
        completed = utc_now()
        if status != 200:
            raise RuntimeError(f"Unexpected HTTP status {status} for {spec['url']}")
        if urlparse(final_url).hostname != "owa.hnx.vn":
            raise RuntimeError(f"Unexpected final host for official HNX source: {final_url}")
        if content_type != "application/pdf" or not body.startswith(b"%PDF-"):
            raise RuntimeError(f"Expected an HNX PDF for {spec['url']}; got {content_type}")

        digest = hashlib.sha256(body).hexdigest()
        if len(body) != spec["expected_bytes"] or digest != spec["expected_sha256"]:
            raise RuntimeError(
                f"HNX source changed: {spec['file']} bytes={len(body)} sha256={digest}"
            )
        (OUT / spec["file"]).write_bytes(body)

        metadata = {
            "source_url": final_url,
            "captured_source_url": final_url,
            "local_file": spec["file"],
            "source_attribution": spec["source_attribution"],
            "capture_time_basis": CAPTURE_TIME_BASIS,
            "captured_at_utc": completed,
            "document_date": spec["document_date"],
            "last_trade_date": spec["last_trade_date"] or None,
            "prior_ceased_from": spec["prior_ceased_from"] or None,
            "first_trade_date": spec["first_trade_date"] or None,
            "source_claim": spec["source_claim"],
            "source_limitation": spec["source_limitation"],
            "notice_id": spec["notice_id"],
        }
        manifest["captures"].append(
            {
                "symbol": spec["symbol"],
                "source": spec["source"],
                "route": "security_lifecycle_notice",
                "file": spec["file"],
                "request_url": spec["url"],
                "final_url": final_url,
                "http_status": status,
                "content_type": content_type,
                "started_at_utc": started,
                "completed_at_utc": completed,
                "bytes": len(body),
                "sha256": digest,
                "notice_id": spec["notice_id"],
                "document_date": spec["document_date"],
                "last_trade_date": spec["last_trade_date"] or None,
                "prior_ceased_from": spec["prior_ceased_from"] or None,
                "first_trade_date": spec["first_trade_date"] or None,
                "source_attribution": spec["source_attribution"],
                "source_claim": spec["source_claim"],
                "source_limitation": spec["source_limitation"],
            }
        )
        landing_rows.append(
            {
                "symbol": spec["symbol"],
                "source": spec["source"],
                "route": "security_lifecycle_notice",
                "fetched_at": completed,
                "source_url": final_url,
                "local_file": spec["file"],
                "document_date": spec["document_date"],
                "last_trade_date": spec["last_trade_date"],
                "prior_ceased_from": spec["prior_ceased_from"],
                "first_trade_date": spec["first_trade_date"],
                "payload_sha256": digest,
                "payload_size": len(body),
                "media_type": content_type,
                "source_attribution": spec["source_attribution"],
                "source_claim": spec["source_claim"],
                "source_limitation": spec["source_limitation"],
                "capture_time_basis": CAPTURE_TIME_BASIS,
                "metadata_json": json.dumps(metadata, ensure_ascii=False, separators=(",", ":")),
                "body_hex": body.hex(),
            }
        )

    (OUT / "landing_stage_gdw_20261102.csv").parent.mkdir(parents=True, exist_ok=True)
    with (OUT / "landing_stage_gdw_20261102.csv").open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=LANDING_FIELDS, lineterminator="\n")
        writer.writeheader()
        writer.writerows(landing_rows)

    event_claim = (
        "Official HNX Notice 1385/TB-SGDHN dated 2018-11-21 states that GDW's "
        "UPCoM registration cancellation is effective 2018-12-07 and that "
        "2018-12-06 is its last trading day at HNX. Official HNX Notice "
        "1458/TB-SGDHN dated 2018-12-06 states that the first HNX trading date "
        "is 2018-12-18. These records establish the venue endpoints only; no "
        "day-level trading, suspension, or delisting state is inferred for "
        "the intervening sessions. HNX's separate 2018-12-06 daily report "
        "records zero matched volume despite the official final-session date."
    )
    event_fields = [
        "symbol",
        "prior_venue",
        "venue",
        "prior_trade_date",
        "effective_date",
        "prior_ceased_from",
        "source_notice_id",
        "continuity_notice_id",
        "source_file",
        "continuity_file",
        "reviewed_claim",
    ]
    event = {
        "symbol": "GDW",
        "prior_venue": "UPCOM",
        "venue": "HNX",
        "prior_trade_date": "2018-12-06",
        "effective_date": "2018-12-18",
        "prior_ceased_from": "2018-12-07",
        "source_notice_id": "1385/TB-SGDHN",
        "continuity_notice_id": "1458/TB-SGDHN",
        "source_file": SOURCES[0]["file"],
        "continuity_file": SOURCES[1]["file"],
        "reviewed_claim": event_claim,
    }
    with (OUT / "transfer_event_stage_gdw_20261102.csv").open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=event_fields, lineterminator="\n")
        writer.writeheader()
        writer.writerow(event)

    manifest["capture_complete_time_utc"] = utc_now()
    (OUT / "capture_manifest_gdw_hnx_endpoints_20261102.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print("Captured two official HNX notices; exact byte counts and SHA-256 hashes verified.")


if __name__ == "__main__":
    main()
