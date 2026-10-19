# VNDIRECT reference gap on 2019-01-02

Audit date: 2026-10-19. This evidence resolves the missing VNDIRECT exchange reference on the first trading session of 2019 without changing or deleting source bars.

## Affected Phase 2 rows

Before resolution, the point-in-time reference view had 684 unresolved factors, all on 2019-01-02, where VNDIRECT reported `basicPrice=0`:

| Exchange | Rows | Matched-volume rows | Zero-volume rows |
| --- | ---: | ---: | ---: |
| HNX | 169 | 169 | 0 |
| HOSE | 316 | 316 | 0 |
| UPCoM | 199 | 176 | 23 |
| **Total** | **684** | **661** | **23** |

The zero-volume UPCoM rows remain in the history. VNDIRECT's zero `basicPrice` is preserved as the original source value; the separate override ledger records the resolved factor and evidence.

## Public corporate-action records

The [VSDC rights-exercise calendar for record date 2019-01-03](https://vsdc.vn/en/lich-giao-dich?date=03%2F01%2F2019&tab=LICH_THQ) returns four notices:

| Symbol | Notice | Effect on 2019-01-02 reference |
| --- | --- | --- |
| FTV | 2019 extraordinary general meeting | None |
| DSN | 2019 annual general meeting and first advance payment of 2018 cash dividend | Cash dividend; reference-price adjustment |
| HCB | First advance payment of 2018 cash dividend | Cash dividend; HCB has no row in the current `core.symbols` universe |
| PCN | 2019 extraordinary general meeting | None |

The official [VSD notice for DSN](https://vsdc.vn/en/ad/125616) gives a record date of 2019-01-03 and a cash payment of VND 3,600 per share. DSN's prior close was VND 62,900. The [published ex-right calculation](https://cophieu68.vn/quote/event_calc.php?id=dsn) gives the theoretical reference as VND 59,300, so the adjustment ratio is:

```text
59.3 / 62.9 = 0.9427662957074722
```

VNDIRECT's DSN bar has a valid matched volume of 3,860 and a close of VND 58,500. The close is retained as an observed market price; the adjustment uses the theoretical reference, not the session close.

The archived VNDIRECT adjusted-snapshot ratios across the other 1,277 symbols with a January 2 bar and a prior-session bar stay within the snapshot's rounding range around 1.0 (0.999055–1.000291). Together with the VSDC calendar, this supports a 1.0 factor for the other unresolved in-scope bars. HCB's 2019 dividend is outside this current-symbol VNDIRECT history because HCB is absent from `core.symbols`; the master build spec records the current-listing survivorship caveat.

## Database resolution

Migration `030_vndirect_2019_reference_resolution.sql` records each affected symbol/date in `core.vndirect_reference_adjustment_overrides`:

- DSN uses the source-backed factor `59.3/62.9` and links to the VSD notice and the ex-right calculation.
- The other 683 factors are explicitly recorded as `NO_ACTION` at 1.0 with the VSDC calendar and a public event summary.
- The original VNDIRECT bars, including zero `basicPrice`, are untouched. The as-of functions consume the resolved factor, so all valid in-scope rows remain available to Phase 2.

The override ledger's `evidence_note` and URLs provide per-symbol audit lineage. The migration tests also cover the DSN dividend case, a no-action case, preservation of raw zero `basicPrice`, and full-history as-of output.
