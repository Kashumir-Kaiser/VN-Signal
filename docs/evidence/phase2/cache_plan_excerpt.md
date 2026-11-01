# Adjustment-cache plan excerpt

Source: PostgreSQL server log `postgresql-2026-10-20_185517.log`, captured during the rollback-only 2020 probe on 2026-10-20. The logged statement was `SELECT feat.prepare_phase2_adjustment_rows(false)` and completed in 89,982.849 ms.

The top-level buffer report was:

```text
Buffers: shared hit=3870 read=99866 dirtied=46 written=1,
         local hit=50902 read=185330 dirtied=51717 written=103493,
         temp read=437750 written=448385
```

At 8 KiB per PostgreSQL block, the temporary work files read about 3.34 GiB and wrote about 3.42 GiB during this sample. The plan materialized the 2,844,683-row `source_rows` CTE to about 667 MiB on disk and the `ordered` CTE to about 830 MiB. Its largest hash step processed 2,844,683 rows in eight batches (122,881 KiB memory), and a 1,823,358-row hash aggregate used five batches with 48,208 KiB of disk spill.

This explains why adjustment-cache creation is I/O sensitive. The 2020 retry logged 8m17.8s for this stage versus 89.98s in the rollback probe. It does not explain the separate 14m42.5s market-context notice or prove that the symbol-batch insertion caused the whole-call timeout; those plans remain unmeasured.
