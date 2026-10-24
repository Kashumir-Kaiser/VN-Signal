# Phase 2 source-input inventory — 2026-10-22

This inventory distinguishes stored evidence, documented capabilities, and
unverified historical coverage. Documentation does not establish actual account
quota, route availability, or historical completeness on the registered machine.
No vendor data calls were made for this inventory.

| Required input | Existing evidence | Work still required |
| --- | --- | --- |
| Daily ceiling/floor prices | Exact-date VNDIRECT Finfo bodies under `docs/probe/phase1-vndirect-api-verification-20261019/raw/` contain `ceilingPrice`, `floorPrice`, and `basicPrice`. The production history importer preserves entire HTTP bodies in `raw.landings`; migration 028 already projects other fields from those bodies by landing/row. | Run the archived-row coverage diagnostic before assuming more history is needed. Validate values and lineage; implement source-based limits and their feature/label calculations. Do not infer limit prices from approximate percentage moves. |
| Listed shares | The archived VCI company profile `docs/probe/company/batch/FPT-000000000496.json` has `issued_share` observed in October 2026. | Validate a dated listed-share source. Current issued shares cannot substitute historical listed shares. The observation table in migration 036 is storage, not a working historical collector/calculator. |
| ICB level 2 | Full-universe VCI listing captures around 2026-10-16/18 preserve `icb_code_lv2`; ingestion keeps observation times and raw lineage. | Historical dated classifications are not established. Use current observations only from their availability time forward; implement PIT industry calculations and source coverage reporting. |
| VN30/VNMID/VNSML and sector histories | Existing local evidence establishes VNINDEX history. Official v5 reference docs list `VN30`, `VNMID`, and `VNSML` and describe index OHLCV. | Audit the actual source/symbol routes and requested dates on the registered machine through the recorded gateway before collection. Implement each required cross-index/sector calculation with the one-session cross-asset lag. |
| Tết calendar | `docs/probe/phase1-calendar-overrides-2019-2026.sql` preserves official closure evidence. Probe metadata describes a market-event route, but does not contain the event rows. | Preserve dated official event/publication records and implement PIT sessions-to/from-event features. Closure bounds and route metadata alone do not prove a historical event-availability archive. |
| Intraday | Storage and lineage constraints exist; the master spec makes this optional and off by default. | Keep disabled until real one-minute data is archived and audited. |
| Fundamentals | PIT storage, mapping and builders exist. Current archive coverage and durable chunk completion remain unaudited in this recovery pass. | Run `phase2_fundamentals_pit_coverage.sql`; finish valid archive chunks and document genuinely unavailable periods without inventing historical statements. |

The [official Reference documentation](https://www.vnstocks.com/docs/vnstock/tham-chieu-reference)
defines VCI `issued_share` as issued shares and describes current company and
industry mappings; it does not document a historical listed-share or effective-
dated ICB endpoint. Its index catalog identifies the three requested HOSE index
symbols. The [official Market documentation](https://www.vnstocks.com/docs/vnstock/thi-truong-market)
describes `Market().index(symbol).ohlcv()` and source parameters. Those route
descriptions are leads for a machine audit, not evidence that the required
histories or numerical quotas are available.
