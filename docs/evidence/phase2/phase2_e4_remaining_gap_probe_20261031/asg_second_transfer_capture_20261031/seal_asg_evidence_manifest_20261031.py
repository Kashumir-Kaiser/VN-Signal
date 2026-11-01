#!/usr/bin/env python3
"""Seal the ASG primary-source, staging, import, and current-census artifacts."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path


PACKET = Path(__file__).resolve().parent
REPO = PACKET.parents[4]
MANIFEST = PACKET / "evidence_manifest_asg_20261031.json"
DISCOVERY = json.loads((PACKET / "capture_manifest_asg_20261031.json").read_text(encoding="utf-8"))
HOSE = json.loads((PACKET / "hose_first_trade_capture_manifest_asg_20261031.json").read_text(encoding="utf-8"))
FILES = [
    "docs/evidence/phase2/phase2_e4_remaining_gap_probe_20261031/capture_asg_second_transfer_20261031.py",
    "docs/evidence/phase2/phase2_e4_remaining_gap_probe_20261031/capture_asg_hose_first_trade_20261031.py",
    "docs/evidence/phase2/phase2_e4_remaining_gap_probe_20261031/prepare_asg_second_transfer_stages_20261031.py",
    "docs/evidence/phase2/phase2_e4_remaining_gap_probe_20261031/hnx_disclosure_probe_20261031/hnx_disclosure_probe_manifest_20261031.json",
    "docs/evidence/phase2/phase2_e4_remaining_gap_probe_20261031/hnx_disclosure_probe_20261031/ASG_NY_29-01-2021_26-12-2021_p1.html",
    "docs/evidence/phase2/phase2_e4_remaining_gap_probe_20261031/asg_second_transfer_capture_20261031/capture_manifest_asg_20261031.json",
    "docs/evidence/phase2/phase2_e4_remaining_gap_probe_20261031/asg_second_transfer_capture_20261031/hose_first_trade_capture_manifest_asg_20261031.json",
    "docs/evidence/phase2/phase2_e4_remaining_gap_probe_20261031/asg_second_transfer_capture_20261031/landing_stage_asg_20261031.csv",
    "docs/evidence/phase2/phase2_e4_remaining_gap_probe_20261031/asg_second_transfer_capture_20261031/transfer_event_stage_asg_20261031.csv",
    "docs/evidence/phase2/phase2_e4_remaining_gap_probe_20261031/asg_second_transfer_capture_20261031/stage_manifest_asg_20261031.json",
    "docs/evidence/phase2/phase2_e4_remaining_gap_probe_20261031/asg_second_transfer_capture_20261031/import_asg_transfer_reportclone_20261031.sql",
    "docs/evidence/phase2/phase2_e4_remaining_gap_probe_20261031/asg_second_transfer_capture_20261031/import_asg_transfer_reportclone_20261031.log",
    "docs/evidence/phase2/phase2_e4_remaining_gap_probe_20261031/asg_second_transfer_capture_20261031/replay_asg_transfer_reportclone_20261031.log",
    "docs/evidence/phase2/phase2_e4_remaining_gap_probe_20261031/asg_second_transfer_capture_20261031/seal_asg_evidence_manifest_20261031.py",
    "docs/evidence/phase2/phase2_e4_remaining_gap_probe_20261031/asg_second_transfer_capture_20261031/README.md",
    "docs/evidence/phase2/phase2_e4_currenthash_gap_pairs_20261031_postasg1.sql",
    "docs/evidence/phase2/phase2_e4_currenthash_gap_pairs_20261031_postasg1.csv",
    "docs/evidence/phase2/phase2_e4_currenthash_gap_pairs_20261031_postasg1.log",
    "docs/evidence/phase2/phase2_e4_feature_endpoint_semantics_20261031_postasg1.sql",
    "docs/evidence/phase2/phase2_e4_feature_endpoint_semantics_20261031_postasg1.csv",
    "docs/evidence/phase2/phase2_e4_feature_endpoint_semantics_20261031_postasg1.log",
    "docs/evidence/phase2/phase2_e4_currenthash_postasg1_20261031.md",
    "docs/BUILD_STATUS.md",
    "docs/DECISIONS.md",
    "tmp/pdfs/asg_second_transfer_source_review_20261031/hnx_asg-1.png",
    "tmp/pdfs/asg_second_transfer_source_review_20261031/hose_asg-1.png",
]
for capture_manifest in (DISCOVERY, HOSE):
    for capture in capture_manifest["captures"]:
        FILES.append(str((PACKET / capture["file"]).relative_to(REPO)).replace("\\", "/"))


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    records = []
    for relative in sorted(set(FILES)):
        path = REPO / Path(relative)
        if not path.is_file():
            raise SystemExit(f"required evidence file is missing: {relative}")
        body = path.read_bytes()
        records.append({"path": relative, "bytes": len(body), "sha256": sha256(path)})
    manifest = {
        "schema_version": 1,
        "scope": "ASG's 2021 HNX-to-HOSE transfer endpoint review, guarded report-clone import, replay, and post-import E4 census.",
        "feature_hash": "28089ed13c1be5a19865bc9cea34c44cb84f3e460ee3f3f2ee837a853d317f6b",
        "target_database": "vnsignal_phase2_report_20261019 (disposable report clone)",
        "event_id": 288,
        "strict_transfer_view": "PASS",
        "first_import": {"signed_endpoint_landings": 2, "transfer_events": 1},
        "idempotent_replay": {"new_endpoint_landings": 0, "new_transfer_events": 0, "strict_transfer_view": "PASS"},
        "source_facts": {
            "final_hnx_trading_day": "2021-09-21",
            "prior_ceased_from": "2021-09-22",
            "prior_ceased_from_basis": "first effective exchange session after the source-stated final HNX trading date; not a separately stated legal cancellation date",
            "first_hose_trading_day": "2021-09-27",
            "shares": 75653891,
            "gap_sessions": 3,
            "intervening_bars": 0,
            "intervening_source_rows": 0,
        },
        "post_import_e4_census": {
            "gap_intervals": 221,
            "missing_effective_sessions": 3225,
            "strictly_verified_transfers": 216,
            "strictly_verified_transfer_sessions": 1519,
            "unmatched_intervals": 5,
            "unmatched_sessions": 1706,
        },
        "files": records,
    }
    MANIFEST.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"files_sealed": len(records), "manifest": MANIFEST.name,
                      "manifest_sha256": sha256(MANIFEST)}, indent=2))


if __name__ == "__main__":
    main()
