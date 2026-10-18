-- Record projection rebuilds from immutable archived market frames.
BEGIN;

CREATE TABLE IF NOT EXISTS ops.bar_quality_reprocess_audit (
    audit_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    job_id bigint NOT NULL REFERENCES ops.ingest_jobs(job_id),
    landing_id bigint NOT NULL REFERENCES raw.landings(landing_id),
    previous_state text NOT NULL CHECK (previous_state IN ('BLOCKED','PARTIAL')),
    resulting_state text NOT NULL CHECK (resulting_state IN ('COMPLETED','PARTIAL')),
    previous_issue_count integer NOT NULL CHECK (previous_issue_count >= 0),
    resulting_issue_count integer NOT NULL CHECK (resulting_issue_count >= 0),
    validator_version text NOT NULL CHECK (length(validator_version) BETWEEN 1 AND 64),
    reprocessed_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (landing_id, validator_version)
);

CREATE INDEX IF NOT EXISTS bar_quality_reprocess_job_idx
    ON ops.bar_quality_reprocess_audit(job_id, reprocessed_at);

COMMIT;
