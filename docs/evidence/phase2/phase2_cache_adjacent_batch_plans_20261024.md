# Adjacent cache-batch plan diagnostic — 2026-10-24

The failed 071 preflight's measured 15/30/60 totals were 827/3495/4544 ms (maximum adjacent exponent 2.079). Its two 15-symbol batches within the 30 sample took 376.795/2030.198 ms; finalize took 963.020 ms. The 60 sample's first two identical symbol sets took 1186.788/940.104 ms. Thus the same batch was not timed consistently within that run.

A new rollback-only EXPLAIN ANALYZE diagnostic used the same first and second 15-symbol sets, jit off, work_mem 8MB, maintenance_work_mem 16MB, and enable_nestloop off. Helper execution times were 345.670/473.113/321.769/422.549 ms in first/second/first/second order. Plans contain neither Nested Loop nor Recursive Union. These are helper query timings, not complete probe timings, and do not establish a passing full-cache scaling gate. Plan evidence includes row estimates, buffer traffic, and temp writes. Source CTE estimates are materially low (some downstream estimates of two rows versus tens of thousands actual); the bounded helper still finished in under half a second in this diagnostic.

Files: phase2_cache_adjacent_batch_plans_20261024.psql and .log. No persistent feature or market data changes. The failed preflight remains failed. Next investigation: complete probe setup/finalization variability and reproducible benchmark strategy; preserve the 1.3 limit.
