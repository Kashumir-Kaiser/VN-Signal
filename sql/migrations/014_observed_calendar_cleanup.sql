-- Keep bar-observed calendar evidence reversible when canonical bars move or
-- are removed. Event sources and operator notes remain independently intact.
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
            WHEN 'observed_bars'=ANY(string_to_array(existing.source,'+')) THEN existing.source
            ELSE concat_ws('+',nullif(existing.source,''),'observed_bars')
        END,
        notes=CASE
            WHEN position('Observed canonical daily bar' in coalesce(existing.notes,''))>0 THEN existing.notes
            ELSE concat_ws('; ',nullif(existing.notes,''),'Observed canonical daily bar')
        END;
END
$$;

CREATE OR REPLACE FUNCTION core.remove_observed_bar_session(p_trade_date date)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    remaining_source text;
    remaining_notes text;
BEGIN
    IF EXISTS (SELECT 1 FROM core.bars_daily WHERE trade_date=p_trade_date) THEN
        RETURN;
    END IF;

    SELECT
        coalesce((
            SELECT string_agg(btrim(part), '+' ORDER BY ordinal)
            FROM unnest(string_to_array(c.source,'+')) WITH ORDINALITY AS src(part,ordinal)
            WHERE btrim(part)<>'' AND btrim(part)<>'observed_bars'
        ),''),
        coalesce((
            SELECT string_agg(btrim(part), '; ' ORDER BY ordinal)
            FROM unnest(string_to_array(coalesce(c.notes,''),';')) WITH ORDINALITY AS note(part,ordinal)
            WHERE btrim(part)<>'' AND btrim(part)<>'Observed canonical daily bar'
        ),'')
      INTO remaining_source,remaining_notes
      FROM core.calendar c
     WHERE c.trade_date=p_trade_date
       AND ('observed_bars'=ANY(string_to_array(c.source,'+'))
            OR position('Observed canonical daily bar' in coalesce(c.notes,''))>0);

    IF NOT FOUND THEN
        RETURN;
    END IF;

    IF remaining_source='' AND remaining_notes='' THEN
        DELETE FROM core.calendar WHERE trade_date=p_trade_date;
    ELSE
        UPDATE core.calendar
           SET source=remaining_source,
               notes=nullif(remaining_notes,'' )
         WHERE trade_date=p_trade_date;
    END IF;
END
$$;

-- Remove stale observed-bar contributions left by earlier trigger versions.
DO $$
DECLARE stale_date date;
BEGIN
    FOR stale_date IN
        SELECT c.trade_date
          FROM core.calendar c
         WHERE 'observed_bars'=ANY(string_to_array(c.source,'+'))
           AND NOT EXISTS (SELECT 1 FROM core.bars_daily b WHERE b.trade_date=c.trade_date)
    LOOP
        PERFORM core.remove_observed_bar_session(stale_date);
    END LOOP;
END
$$;

CREATE OR REPLACE FUNCTION core.bars_daily_calendar_trigger()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_OP='INSERT' THEN
        PERFORM core.record_observed_bar_session(NEW.trade_date);
        RETURN NEW;
    ELSIF TG_OP='UPDATE' THEN
        IF OLD.trade_date IS DISTINCT FROM NEW.trade_date THEN
            PERFORM core.remove_observed_bar_session(OLD.trade_date);
            PERFORM core.record_observed_bar_session(NEW.trade_date);
        END IF;
        RETURN NEW;
    ELSE
        PERFORM core.remove_observed_bar_session(OLD.trade_date);
        RETURN OLD;
    END IF;
END
$$;

DROP TRIGGER IF EXISTS bars_daily_observed_calendar ON core.bars_daily;
CREATE TRIGGER bars_daily_observed_calendar
AFTER INSERT OR DELETE OR UPDATE OF trade_date ON core.bars_daily
FOR EACH ROW EXECUTE FUNCTION core.bars_daily_calendar_trigger();

COMMENT ON FUNCTION core.remove_observed_bar_session(date) IS
    'Removes only bar-derived calendar provenance when its final canonical bar is moved or deleted.';
COMMENT ON TRIGGER bars_daily_observed_calendar ON core.bars_daily IS
    'Maintains the calendar union for canonical bar inserts, date moves, and deletes while preserving independent evidence.';

COMMIT;
