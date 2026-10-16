-- A singleton database guard makes the same account/device quota visible to
-- every process, even after restart. A new authoritative absolute usage read
-- is required before the previous guard expires (<= 10 minutes).
BEGIN;
CREATE TABLE IF NOT EXISTS ops.quota_guard (
    singleton boolean PRIMARY KEY DEFAULT true CHECK (singleton),
    verified_at timestamptz NOT NULL,
    expires_at timestamptz NOT NULL,
    day_key date NOT NULL,
    call_budget integer NOT NULL CHECK (call_budget >= 0),
    spent integer NOT NULL DEFAULT 0 CHECK (spent >= 0 AND spent <= call_budget),
    min_spacing_ms bigint NOT NULL CHECK (min_spacing_ms >= 1000),
    last_not_before timestamptz,
    CHECK (expires_at > verified_at AND expires_at <= verified_at + interval '10 minutes')
);
COMMIT;
