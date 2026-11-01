# Tenure proof scope and source review

The Master Spec requires at least250 listed sessions. The2026-10-18 decision
explicitly accepted250 distinct source-verified positive execution dates as a
conservative sufficient condition, strictly before the signal. Fewer positive
dates do not prove fewer listed sessions: zero-volume/suspended listed days are
not counted by that lower bound. Migration080's exact legal-event route is useful
but demanding it for every row tightened the earlier accepted contract. It must
not become an unrequested requirement for an exhaustive legal history.

## Source findings

VCI exact-row archive076/077 establishes original-row provenance but its captured
OHLCV rows do not carry a dated exchange or immutable instrument identifier. The
installed vnstock5.0.3 compatibility facade delegates symbol-based history to
`Market().equity(...).history(source="vci")`. Provider `organisation` identifies
the publisher, not the security. No affirmative public route documentation was
found closing OTC coverage or ticker-reuse ambiguity. Do not blanket-approve all
VCI observations as legal/session proof just because lineage is exact.

The actual archived VNDIRECT response has native per-row `code`, `date`, `type`,
`floor` and matched `nmVolume` fields. A real ACB check shows `STOCK/HNX` on
2018-10-01 and2020-12-01, and `STOCK/HOSE` on2020-12-09 and2026-10-16. This
demonstrates dated venue metadata rather than merely a current exchange copied
onto all history. See `phase2_execution_identity_source_fields_20261024.log` and
`phase2_execution_venue_history_check_20261024.log`. This is one validation case,
not a claim of complete source-wide legal coverage.

## Next implementation

Add an alternative sufficient-proof route using exact original VNDIRECT rows:
verify whole landing bytes/hash/decoded body; source and route; zero-based row
pointer; exact code/date/rawOHLC/matched volume versus canonical source bar;
explicit `STOCK` type and supported dated public-market venue; finite positive
matched volume and true market session. Preserve canonical/source fingerprints
and qualification status in append-only observations. Never infer an instrument
identifier from publisher organisation or a current exchange.

The identity contract must be explicit: this project keys provider security
history by its canonical symbol identity; known reuse/relisting/identity conflicts
must fence the fallback. Do not claim an ISIN guarantee that the source does not
provide. Keep080 as the stronger exact/legal path, including known closures and
conflicts. For an eligible qualified execution lower bound, >=250 suffices;
<250 stays indeterminate. Persist proof method so a lower bound is never labeled
as an exact legal age. Hash all prior proof/current canonical dependencies and
known lifecycle fences. Materialize indexed prefix counts once per label chunk;
avoid a250-row historical query or source JSON decode for every candidate/date.

This route is not implemented or approved as successful yet. Synthetic negative
tests, real qualification/identity coverage and full offline CI are required
before relying on it. Do not change V3 price feature meanings or restart the
running price build for this label/membership-only correction.

## Official admission research

The DL1 HNX first-trading notice50254 has been captured and imported as an intact
raw source document: header26February2010, first session10March2010, issuer
letter16/2010/CV-DLIDPS dated22February2010. See
`hnx_dl1_admission_20261024/manifest.json`; import first1/repeat0. It proves that
admission claim, not exhaustive later legal continuity. No real legal ledger
event or eligibility has been inferred from it.

Official VSDC notice https://vsdc.vn/vi/ad/72545 is a research lead for the2020
DL1 issuer rename and ISIN VN000000DL14; the HNX current profile and later signed
annual reports link the later Alpha Seven name. These leads have not been
materialized/reviewed as complete historical continuity evidence. FPT's original
signed admission notice and TCB's original2018 notice remain unlocated; issuer
retrospectives are not original publication snapshots.
