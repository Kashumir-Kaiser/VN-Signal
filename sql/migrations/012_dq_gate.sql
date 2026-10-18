-- Inputs that establish the explicitly selected Tier A universe and the
-- independently obtained cross-source comparison sample for a DQ run.
BEGIN;
CREATE TABLE IF NOT EXISTS ops.dq_tier_a_symbols (
    trade_date date NOT NULL,
    symbol_id bigint NOT NULL REFERENCES core.symbols(symbol_id),
    PRIMARY KEY(trade_date,symbol_id)
);
COMMENT ON TABLE ops.dq_tier_a_symbols IS
    'Explicit dated Tier A membership evidence. Populate only from a verified universe selection; an empty date blocks DQ.';
CREATE TABLE IF NOT EXISTS ops.dq_cross_source_samples (
    trade_date date NOT NULL,
    symbol text NOT NULL,
    primary_source text NOT NULL CHECK(length(btrim(primary_source))>0),
    primary_close double precision NOT NULL,
    secondary_source text NOT NULL CHECK(length(btrim(secondary_source))>0),
    secondary_close double precision NOT NULL,
    selected_for_gate boolean NOT NULL DEFAULT false,
    PRIMARY KEY(trade_date,symbol),
    CHECK(lower(primary_source)<>lower(secondary_source))
);
COMMENT ON TABLE ops.dq_cross_source_samples IS
	'Independently observed same-date closes from distinct sources. Insert reconciled evidence and explicitly select exactly 30 Tier A pairs for a gate run.';
COMMENT ON COLUMN ops.dq_cross_source_samples.primary_source IS
    'Source identity for primary_close; must differ from secondary_source.';
COMMENT ON COLUMN ops.dq_cross_source_samples.selected_for_gate IS
    'Explicit sample membership; the runner consumes exactly 30 selected Tier A rows and never chooses a sample itself.';
CREATE OR REPLACE VIEW ops.dq_gate_input_readiness AS
WITH tier AS (
    SELECT trade_date,count(*)::bigint AS tier_a_symbols
    FROM ops.dq_tier_a_symbols GROUP BY trade_date
), pairs AS (
    SELECT x.trade_date,count(*)::bigint AS independent_source_pairs
    FROM ops.dq_cross_source_samples x
    JOIN core.symbols s ON s.symbol=x.symbol
    JOIN ops.dq_tier_a_symbols u ON u.symbol_id=s.symbol_id AND u.trade_date=x.trade_date
    WHERE x.selected_for_gate GROUP BY x.trade_date
)
SELECT coalesce(tier.trade_date,pairs.trade_date) AS trade_date,
       coalesce(tier.tier_a_symbols,0) AS tier_a_symbols,
       coalesce(pairs.independent_source_pairs,0) AS independent_source_pairs,
       coalesce(pairs.independent_source_pairs,0)=30 AS cross_source_ready
FROM tier FULL OUTER JOIN pairs USING(trade_date);
COMMENT ON VIEW ops.dq_gate_input_readiness IS
    'Read-only readiness counts for explicit DQ evidence inputs; only selected pairs count, and zero/missing counts are not a gate pass.';
CREATE TABLE IF NOT EXISTS ops.dq_gate_results (
    run_id uuid PRIMARY KEY REFERENCES ops.pipeline_runs(run_id),
    trade_date date NOT NULL,
    status text NOT NULL CHECK(status IN ('PASSED','FAILED','STALE')),
    report jsonb NOT NULL,
    recorded_at timestamptz NOT NULL DEFAULT now()
);
COMMIT;
