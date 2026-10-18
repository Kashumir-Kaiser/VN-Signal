-- The session calendar is the union of verified event-calendar rows and
-- dates on which canonical daily bars were observed. Manual overrides remain
-- authoritative at read time.
BEGIN;

CREATE OR REPLACE FUNCTION core.record_observed_bar_session(p_trade_date date)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO core.calendar AS existing(trade_date,is_session,source,notes)
    VALUES (p_trade_date,true,'observed_bars','Observed canonical daily bar')
    ON CONFLICT (trade_date) DO UPDATE SET
        is_session=true,
        source=CASE
            WHEN position('observed_bars' in existing.source)>0 THEN existing.source
            ELSE concat_ws('+',nullif(existing.source,''),'observed_bars')
        END,
        notes=CASE
            WHEN position('Observed canonical daily bar' in coalesce(existing.notes,''))>0 THEN existing.notes
            ELSE concat_ws('; ',nullif(existing.notes,''),'Observed canonical daily bar')
        END;
END
$$;

-- Reconcile dates already present before installing the future-ingest trigger.
SELECT core.record_observed_bar_session(trade_date)
FROM (SELECT DISTINCT trade_date FROM core.bars_daily) AS observed;

CREATE OR REPLACE FUNCTION core.bars_daily_calendar_trigger()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM core.record_observed_bar_session(NEW.trade_date);
    RETURN NEW;
END
$$;

DROP TRIGGER IF EXISTS bars_daily_observed_calendar ON core.bars_daily;
CREATE TRIGGER bars_daily_observed_calendar
AFTER INSERT OR UPDATE OF trade_date ON core.bars_daily
FOR EACH ROW EXECUTE FUNCTION core.bars_daily_calendar_trigger();

COMMENT ON FUNCTION core.record_observed_bar_session(date) IS
    'Adds a session backed by canonical bar evidence while preserving existing calendar source notes.';
COMMENT ON TRIGGER bars_daily_observed_calendar ON core.bars_daily IS
    'Keeps the effective calendar union current as canonical bars are ingested; manual overrides take precedence in DQ queries.';

COMMIT;
