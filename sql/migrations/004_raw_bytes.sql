-- Preserve exact vendor bytes; jsonb reorders keys/normalizes formatting and
-- therefore cannot be used alone to verify the original payload SHA-256.
-- Legacy rows remain nullable because their exact original bytes are unknown.
BEGIN;
ALTER TABLE raw.landings
    ADD COLUMN IF NOT EXISTS payload_bytes bytea;
ALTER TABLE raw.landings
    DROP CONSTRAINT IF EXISTS landings_payload_bytes_bound;
ALTER TABLE raw.landings
    ADD CONSTRAINT landings_payload_bytes_bound
    CHECK (payload_bytes IS NULL OR octet_length(payload_bytes) BETWEEN 2 AND 10485760);
COMMIT;
