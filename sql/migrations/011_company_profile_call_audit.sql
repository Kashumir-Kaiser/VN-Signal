-- Link each metered company_info dispatch to its already reserved profile
-- attempt. This is a second audit layer, not a second quota reservation.
BEGIN;
CREATE TABLE IF NOT EXISTS ops.company_profile_call_audit (
    attempt_id bigint PRIMARY KEY
        REFERENCES ops.company_profile_attempts(attempt_id),
    not_before timestamptz NOT NULL,
    status text NOT NULL DEFAULT 'RESERVED'
        CHECK (status IN ('RESERVED','DISPATCHED','SUCCEEDED','FAILED',
                          'RATE_LIMITED','CANCELLED')),
    reserved_at timestamptz NOT NULL DEFAULT now(),
    dispatched_at timestamptz,
    finished_at timestamptz,
    reason text,
    CHECK (length(coalesce(reason,''))<=120),
    CHECK (dispatched_at IS NULL OR dispatched_at>=reserved_at),
    CHECK (finished_at IS NULL OR finished_at>=reserved_at),
    CHECK ((status IN ('RESERVED','DISPATCHED'))=(finished_at IS NULL)),
    CHECK (status NOT IN ('SUCCEEDED','FAILED','RATE_LIMITED')
           OR dispatched_at IS NOT NULL)
);
COMMIT;
