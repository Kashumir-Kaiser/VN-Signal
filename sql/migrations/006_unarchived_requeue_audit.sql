-- Phase 1: explicit audit of manual, no-quota unarchived legacy job requeues.
-- A requeue is not a vendor call and never credits earlier reservations.
BEGIN;
CREATE TABLE IF NOT EXISTS ops.ingest_requeue_audit (
    audit_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    job_id bigint NOT NULL REFERENCES ops.ingest_jobs(job_id),
    prior_attempt integer NOT NULL CHECK (prior_attempt >= 1),
    prior_error_type text NOT NULL,
    reason text NOT NULL CHECK (reason IN ('UNARCHIVED_LEGACY_FRAME')),
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE(job_id,prior_attempt)
);
CREATE INDEX IF NOT EXISTS ingest_requeue_audit_job_idx
    ON ops.ingest_requeue_audit(job_id,created_at);
COMMIT;
