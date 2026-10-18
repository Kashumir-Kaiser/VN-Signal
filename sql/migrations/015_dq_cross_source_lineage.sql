-- A DQ cross-source close must point to exact bytes and an exact source row.
BEGIN;
ALTER TABLE ops.dq_cross_source_samples
    ADD COLUMN IF NOT EXISTS primary_landing_id bigint REFERENCES raw.landings(landing_id);
ALTER TABLE ops.dq_cross_source_samples
    ADD COLUMN IF NOT EXISTS primary_source_row integer;
ALTER TABLE ops.dq_cross_source_samples
    ADD COLUMN IF NOT EXISTS secondary_landing_id bigint REFERENCES raw.landings(landing_id);
ALTER TABLE ops.dq_cross_source_samples
    ADD COLUMN IF NOT EXISTS secondary_source_row integer;
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                   WHERE conrelid='ops.dq_cross_source_samples'::regclass
                     AND conname='dq_cross_source_lineage_complete') THEN
        ALTER TABLE ops.dq_cross_source_samples
        ADD CONSTRAINT dq_cross_source_lineage_complete CHECK (
        (primary_landing_id IS NULL AND primary_source_row IS NULL
         AND secondary_landing_id IS NULL AND secondary_source_row IS NULL)
        OR
        (primary_landing_id IS NOT NULL AND primary_source_row IS NOT NULL AND primary_source_row >= 0
         AND secondary_landing_id IS NOT NULL AND secondary_source_row IS NOT NULL AND secondary_source_row >= 0
         AND primary_landing_id <> secondary_landing_id)
        );
    END IF;
END $$;
COMMENT ON COLUMN ops.dq_cross_source_samples.primary_landing_id IS
    'Raw source landing whose exact payload bytes provide primary_close; legacy unlineaged evidence remains unusable.';
COMMENT ON COLUMN ops.dq_cross_source_samples.primary_source_row IS
    'Zero-based row index in the exact primary landing payload.';
COMMENT ON COLUMN ops.dq_cross_source_samples.secondary_landing_id IS
    'Raw source landing whose exact payload bytes provide secondary_close; legacy unlineaged evidence remains unusable.';
COMMENT ON COLUMN ops.dq_cross_source_samples.secondary_source_row IS
    'Zero-based row index in the exact secondary landing payload.';

CREATE OR REPLACE VIEW ops.dq_gate_input_readiness AS
WITH tier AS (
    SELECT trade_date,count(*)::bigint AS tier_a_symbols
    FROM ops.dq_tier_a_symbols GROUP BY trade_date
), pairs AS (
    SELECT x.trade_date,count(*)::bigint AS independent_source_pairs
    FROM ops.dq_cross_source_samples x
    JOIN core.symbols s ON s.symbol=x.symbol
    JOIN ops.dq_tier_a_symbols u ON u.symbol_id=s.symbol_id AND u.trade_date=x.trade_date
    WHERE x.selected_for_gate
      AND x.primary_landing_id IS NOT NULL AND x.primary_source_row IS NOT NULL
      AND x.secondary_landing_id IS NOT NULL AND x.secondary_source_row IS NOT NULL
    GROUP BY x.trade_date
)
SELECT coalesce(tier.trade_date,pairs.trade_date) AS trade_date,
       coalesce(tier.tier_a_symbols,0) AS tier_a_symbols,
       coalesce(pairs.independent_source_pairs,0) AS independent_source_pairs,
       coalesce(pairs.independent_source_pairs,0)=30 AS cross_source_ready
FROM tier FULL OUTER JOIN pairs USING(trade_date);
COMMENT ON VIEW ops.dq_gate_input_readiness IS
    'Readiness counts only explicitly selected Tier A pairs with complete landing/row lineage; the DQ runner separately verifies checksums, rows, source attribution and distinct provider organisations.';
COMMIT;
