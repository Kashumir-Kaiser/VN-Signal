# GDW prior-venue endpoint search — 2026-10-31

## Current finding

The current V3 feature-set census has one unresolved non-lifecycle gap:
GDW, feature rows dated 2018-12-06 and 2018-12-18, spanning seven effective
sessions (2018-12-07, 10, 11, 12, 13, 14, and 17). The disposable clone has
no intervening bar or source-archive row.
The endpoint audit shows the 2018-12-06 feature row is not marked traded, and
the last positive-volume bar on or before it is 2018-12-03. Therefore the
feature-row endpoint is not evidence that GDW traded on December 6.

No transfer event has been imported for this interval. The last UPCoM trading
date and the exact prior-venue cessation boundary remain unverified from a
captured authoritative source. Do not assign trade, no-trade, suspension, or
delisting status to individual gap sessions.

## Authoritative evidence retained

- Official HNX article 60003364 and its signed attachment establish that
  GDW's first HNX trading day was 2018-12-18 and state 9,500,000 shares.
- HNX Decision 651/QD-SGDHN and its capture establish the HNX listing approval.
- HNX UPCoM board-resolution article 298983 and its attachment show the
  company's transition process, but do not provide an explicit UPCoM final
  trading day or cancellation-effective date.
- The captured official HNX UPCoM issuer-disclosure query for
  2018-09-07 through 2019-03-18 returned the board-resolution article but no
  explicit final-trading-day or cancellation notice.
- The issuer archive search index exposes an announcement titled “Công bố
  việc hủy đăng ký giao dịch cổ phiếu Công ty” dated 2018-11-23 and a separate
  2018-12-05 post about transferring GDW registration/depository data from
  UPCoM to HNX. The archive page does not expose the first announcement's
  attachment contents in the preserved capture. Its old host could not be
  retrieved through a verified TLS connection; certificate checks were not
  bypassed.
- The issuer archive index also lists the 2018 annual report on 2019-03-25
  with an attachment indicator. At the time of this initial search, that
  attachment had not yet been captured or reviewed.
- HNX's official first-trade record and current profile confirm the HNX
  endpoint, but neither establishes the previous UPCoM endpoint.

## Secondary date lead and access limits

CafeF's GDW profile reports 2018-12-07 as the final trading date; other
secondary company profiles repeat that date. This is useful as a lead, but
does not close the source requirement for a strict event import. The official
issuer archive's page listing does not by itself prove that date. The VSDC
The first VSDC transfer-search attempt on 2026-10-31 returned an HTTP 400
response. A successful, bounded capture of the official VSDC transfer notice
was completed on 2026-11-02; it establishes the registration/depository-data
transfer date but not the final UPCoM trading date. A timestamped Wayback CDX
lookup for the issuer article ID returned no archived successful captures;
see `wayback_article_lookup_20261031.txt`.

The next useful sources are the original issuer cancellation notice
attachment, the issuer's 2018 annual-report attachment, or an HNX/VSDC
cancellation or final-trade record with its date and source metadata. Until
obtained, keep GDW unmatched and the E4 status partial.

## 2026-11-01 internet recheck

A fresh web search again found CafeF's GDW profile reporting 2018-12-07 as
the last UPCoM trading date ([profile](https://cafef.vn/du-lieu/gdw/thong-tin-chung.chn),
accessed 2026-11-01). CafeF also carries the 2018-12-06 notice that credits
HNX and states the first HNX trading date was 2018-12-18 ([notice](https://cafef.vn/du-lieu/gdw-1098484/gdw-ngay-18122018-giao-dich-9500000-co-phieu-niem-yet.chn)).
The current HNX profile independently confirms the 2018-12-18 first-trade
date ([HNX profile](https://hnx.vn/cophieu-etfs/chi-tiet-chung-khoan-ny-GDW.html?_des_tab=3)).
These results reinforce the date lead, but the only source found for the
2018-12-07 last-trading date is still a secondary profile. The HNX notice
concerns the new HNX listing and does not state the prior UPCoM final-trade
date. The source requirement therefore remains unmet; no event or session
status was imported from this lead.

## 2026-11-01 issuer-archive follow-up

A new search-index view of the issuer's archive lists “Công bố việc hủy đăng
ký giao dịch cổ phiếu Công ty” dated 2018-11-23 and a separate 2018-12-05
notice about moving GDW's registration and depository data from UPCoM to HNX.
The indexed listing does not expose the notice attachment or its effective
date. The legacy URL
[`giadinhwater.com.vn/Default.aspx?lang=vie&mid=0043&nid=001925`](https://giadinhwater.com.vn/Default.aspx?lang=vie&mid=0043&nid=001925)
still fails normal TLS validation from this host; certificate checks were not
bypassed. The alternate company domain named in the issuer archive footer,
[`capnuocgiadinh.vn`](https://capnuocgiadinh.vn), responds over HTTPS, but its
legacy notice path returns 404 and does not provide the 2018 attachment.

The CafeF profile still reports 2018-12-07 as the final UPCoM trading date,
but remains secondary evidence. The issuer's indexed notice title and date
are not enough to infer its content. No source landing or transfer event was
added; keep GDW and the seven sessions unmatched.

## 2026-11-02 HNX annual-report attachment review

The official HNX listed-market disclosure archive was queried over
2019-03-18–2019-04-05 for GDW. It returned article 309502, “Báo cáo thường
niên 2018,” published 2019-03-26, and its PDF attachment was captured over
HTTPS with normal certificate validation. The reproducible query, article
detail, attachment URL, byte count, and SHA-256 are in
[`capture_manifest.json`](../gdw_hnx_2019_annual_report_capture_20261101/capture_manifest.json);
the capture code is
[`capture_gdw_2019_annual_report_hnx_20261101.py`](../capture_gdw_2019_annual_report_hnx_20261101.py).
The saved 10,009,167-byte PDF has SHA-256
`d0617795ee1592d5180fd144814791d0f63b0478525117df19bc4819a8a3edf6`.

Visual review of the report's corporate-history section (PDF page 4, printed
page 3/22) confirms the company account of the UPCoM listing in 2010 and the
HNX listing date 2018-12-18. That section gives no final UPCoM trading date or
cancellation-effective date. It therefore corroborates the HNX start boundary
but does not resolve which, if any, of the seven gap sessions were UPCoM
trading sessions. The full HNX article/capture remains primary evidence for
the listed-market disclosure; the report's scanned text layer is empty, so
the reviewed page was rendered and checked visually. The secondary
2018-12-07 lead remains unverified from a primary source. No gap-session
status or transfer event was imported; keep E4 partial.

## Captures and logs

- `../gdw_hnx_disclosure_search_20261101/` — read-only recheck against HNX's
  current issuer-disclosure search. The UPCoM query for 2018-09-07 through
  2019-03-18 returned only the 2018-11-08 board-resolution notice. The HNX
  listing query for 2018-11-01 through 2018-12-31 returned the 2018-12-06
  first-HNX-trading notice and a 2018-12-13 margin-list notice. Neither result
  states the last UPCoM trading date or cancellation effective date; the raw
  responses and SHA-256 values are in `capture_manifest.json`.
- `../gdw_hnx_official_capture_20261031_retry1/` — HNX articles, signed PDFs,
  capture manifest, and HNX current-profile pages.
- `../hnx_disclosure_probe_20261031/` — query result pages and manifest for
  GDW's official HNX issuer disclosures.
- `../capture_gdw_hnx_official_records_20261031.py` — HNX record capture
  script.
- `../../phase2_e4_currenthash_gap_pairs_20261031_posttielcm1.csv` — current
  gap row; authoritative reconciliation counts are in the E4 report at
  `../../phase2_e4_currenthash_posttielcm1_20261031.md`.

## 2026-11-02 official transfer and daily-report capture

The VSDC search result and article were captured over HTTPS with normal
certificate validation. The official VSDC record identifies GDW, ISIN
`VN000000GDW9`, transfer from UpCOM to HNX, 9,500,000 registered shares, and
an effective registration/depository-data transfer date of 2018-12-11. The
article says that VSDC would move the registration and depository data between
markets from that date. It does **not** state GDW's final UPCoM trading date or
the exchange's cancellation-effective date. Keep this VSDC date distinct from
both venue endpoints; it is not a substitute for the missing prior-venue
endpoint.

The capture is in
[`gdw_transfer_sources_capture_20261102/`](../gdw_transfer_sources_capture_20261102/)
with reproducible request code at
[`capture_gdw_transfer_sources_20261102.py`](../capture_gdw_transfer_sources_20261102.py).
The capture manifest records the filtered VSDC row, request parameters,
response hashes, and the fact that the short-lived VSDC request token was not
saved. It also records exact-date HNX UPCoM report results:

| Date | GDW rows | Official report field |
| --- | ---: | --- |
| 2018-12-06 | 1 | Total-market volume 0 |
| 2018-12-07 | 0 | No GDW row returned |
| 2018-12-10 | 0 | No GDW row returned |
| 2018-12-11 | 0 | No GDW row returned |

An absent HNX row is recorded only as an absent row. It does not establish
that the security was suspended, delisted, or ineligible to trade on that
session. The already captured HNX signed first-trade notice establishes the
new HNX endpoint of 2018-12-18; it does not establish the old UPCoM endpoint.
The issuer's indexed 2018-11-23 cancellation-notice entry remains a lead: its
attachment could not be retrieved over a verified TLS connection. No GDW
transfer event was imported from these records. Keep the seven-session E4
interval unmatched and E4 partial until a primary source establishes the
prior-venue endpoint.

## 2026-11-02 later HNX notice capture supersedes the unresolved result above

The official HNX-hosted PDF of Notice 1385/TB-SGDHN, dated 2018-11-21, was
retrieved over HTTPS with default certificate validation and visually
reviewed. It identifies GDW and explicitly states that the last trading day
on HNX/UPCoM was **2018-12-06** and registration cancellation took effect
**2018-12-07**. HNX Notice 1458/TB-SGDHN dated 2018-12-06 establishes the
first HNX trading session as **2018-12-18**. This primary-source endpoint pair
shows that secondary profiles reporting December 7 conflate the
cancellation-effective date with the final UPCoM session. VSDC's December 11
registration/depository-data transfer date is a separate custody milestone.

The source bytes, capture metadata, reproducible script, and reviewed event
stage are in
[`gdw_hnx_deregistration_capture_20261102/`](../gdw_hnx_deregistration_capture_20261102/README.md).
Event 292 was added with its two source landings only to disposable report
clone `vnsignal_phase2_report_20261019`; no market bars, features, labels, or
production database rows were changed. HNX's 2018-12-06 daily report records
zero matched volume, so the final-session notice is not treated as proof of an
executed trade. The seven sessions from December 7 through 17 remain
unclassified individually.

The updated current-hash census records 219 strict transfers / 1,539 sessions,
two separately supported CTR/PTM lifecycle cases / 1,686 sessions, and zero
other unresolved intervals. E4 continuity now passes. The contemporaneous
Phase 2 blocker note above is superseded by the later target-readiness audit:
all 225 quarantined weights are outside the eligible/investable cohort, and
the optional PIT model overlay remains disabled by scope. See the [updated E4
report](../gdw_hnx_deregistration_capture_20261102/phase2_e4_currenthash_postgdw_20261102.md),
[target-readiness audit](../../phase2_phase3_training_target_readiness_20261102.log),
and [current status](../../../../BUILD_STATUS.md).
