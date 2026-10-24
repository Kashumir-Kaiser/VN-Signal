-- Durable chunk and step history for resumable Phase 2 materialization.
BEGIN;

CREATE TABLE IF NOT EXISTS ops.feature_chunks (
    build_id text NOT NULL,
    stage text NOT NULL CHECK(stage IN ('features','labels','fundamentals')),
    chunk_key text NOT NULL,
    date_from date NOT NULL,
    date_to date NOT NULL,
    status text NOT NULL DEFAULT 'pending'
        CHECK(status IN ('pending','running','done','failed')),
    rows bigint CHECK(rows IS NULL OR rows>=0),
    started_at timestamptz,
    finished_at timestamptz,
    error text,
    PRIMARY KEY(build_id,stage,chunk_key),
    CHECK(date_from<=date_to),
    CHECK(status NOT IN ('done','failed') OR finished_at IS NOT NULL),
    CHECK(status<>'running' OR finished_at IS NULL)
);

CREATE INDEX IF NOT EXISTS feature_chunks_status_idx
    ON ops.feature_chunks(build_id,stage,status,date_from);

CREATE TABLE IF NOT EXISTS ops.step_runs (
    step_run_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    build_id text NOT NULL,
    stage text NOT NULL CHECK(stage IN ('features','labels','fundamentals')),
    chunk_key text NOT NULL,
    status text NOT NULL CHECK(status IN ('running','done','failed')),
    rows bigint CHECK(rows IS NULL OR rows>=0),
    started_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    finished_at timestamptz,
    duration_ms bigint CHECK(duration_ms IS NULL OR duration_ms>=0),
    error text,
    FOREIGN KEY(build_id,stage,chunk_key)
        REFERENCES ops.feature_chunks(build_id,stage,chunk_key),
    CHECK((status='running')=(finished_at IS NULL))
);

CREATE INDEX IF NOT EXISTS step_runs_build_stage_idx
    ON ops.step_runs(build_id,stage,step_run_id);

COMMENT ON TABLE ops.feature_chunks IS
    'Idempotent Phase 2 feature, label and fundamental-overlay date chunks. Completed chunks survive later failures and are skipped on resume.';
COMMENT ON TABLE ops.step_runs IS
    'Per-attempt Phase 2 stage timings and row counts, including failed or interrupted chunks.';

COMMIT;
