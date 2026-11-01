BEGIN;

SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30min';

CREATE SEQUENCE IF NOT EXISTS ops.phase2_label_dependency_revision_seq
    AS bigint START WITH 1 INCREMENT BY 1 NO MINVALUE NO MAXVALUE CACHE 1;

CREATE OR REPLACE FUNCTION ops.bump_phase2_label_dependency_revision()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=pg_catalog
AS $phase2_label_dependency_revision$
BEGIN
    PERFORM pg_catalog.nextval('ops.phase2_label_dependency_revision_seq'::pg_catalog.regclass);
    RETURN NULL;
END;
$phase2_label_dependency_revision$;

CREATE OR REPLACE FUNCTION ops.phase2_label_dependency_watermark()
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path=pg_catalog
AS $phase2_label_dependency_watermark$
    SELECT last_value::text||':'||is_called::text
      FROM ops.phase2_label_dependency_revision_seq
$phase2_label_dependency_watermark$;

DROP TRIGGER IF EXISTS phase2_label_dependency_features_daily ON feat.features_daily;
CREATE TRIGGER phase2_label_dependency_features_daily
AFTER INSERT OR UPDATE OR DELETE OR TRUNCATE ON feat.features_daily
FOR EACH STATEMENT EXECUTE FUNCTION ops.bump_phase2_label_dependency_revision();

DROP TRIGGER IF EXISTS phase2_label_dependency_labels_daily ON feat.labels_daily;
CREATE TRIGGER phase2_label_dependency_labels_daily
AFTER INSERT OR UPDATE OR DELETE OR TRUNCATE ON feat.labels_daily
FOR EACH STATEMENT EXECUTE FUNCTION ops.bump_phase2_label_dependency_revision();

DROP TRIGGER IF EXISTS phase2_label_dependency_price_limits ON core.daily_price_limit_observations;
CREATE TRIGGER phase2_label_dependency_price_limits
AFTER INSERT OR UPDATE OR DELETE OR TRUNCATE ON core.daily_price_limit_observations
FOR EACH STATEMENT EXECUTE FUNCTION ops.bump_phase2_label_dependency_revision();

-- Raw landings are append-only. Inserts affect a label only when a linked limit
-- observation is materialized (covered above); mutation or truncation of an
-- existing landing still invalidates every label input manifest.
DROP TRIGGER IF EXISTS phase2_label_dependency_raw_landings ON raw.landings;
CREATE TRIGGER phase2_label_dependency_raw_landings
AFTER UPDATE OR DELETE OR TRUNCATE ON raw.landings
FOR EACH STATEMENT EXECUTE FUNCTION ops.bump_phase2_label_dependency_revision();

CREATE OR REPLACE FUNCTION ops.phase2_label_target_chunk_base_input_hash(
    p_date_from date,
    p_date_to date
)
RETURNS text
LANGUAGE plpgsql
STABLE
AS $phase2_label_base_hash_107$
DECLARE
    v_first_signal date;
    v_prior_session date;
    v_hash text;
    v_context text;
    v_prior_state text;
    v_feature_hash text:=feat.phase2_feature_set_hash_v3();
BEGIN
    SELECT min(trade_date) INTO v_first_signal
      FROM core.effective_trading_sessions
     WHERE is_session AND trade_date BETWEEN p_date_from AND p_date_to;

    IF v_first_signal IS NULL THEN
        RETURN ops.phase2_hash_text(
            coalesce(ops.phase2_chunk_input_hash('labels',p_date_from,p_date_to),'')
            ||'|label_dependency_revision=v1|'
            ||ops.phase2_label_dependency_watermark()
        );
    END IF;

    SELECT max(trade_date) INTO v_prior_session
      FROM core.effective_trading_sessions
     WHERE is_session AND trade_date<v_first_signal;

    -- The prior 59-session feature context and linked execution evidence are
    -- invalidated by statement-level source revisions. This avoids serializing
    -- the full multi-year feature and price-limit panels into a giant string.
    v_context:=ops.phase2_label_dependency_watermark();

    SELECT ops.phase2_hash_text(coalesce(
               string_agg(ops.phase2_hash_jsonb(to_jsonb(s)),'' ORDER BY s.symbol_id),''
           ))
      INTO v_prior_state
      FROM feat.phase2_liquidity_tiers_v3 s
     WHERE s.trade_date=v_prior_session AND s.feature_set_hash=v_feature_hash;

    v_hash:=ops.phase2_chunk_input_hash('labels',p_date_from,p_date_to);
    RETURN ops.phase2_hash_text(
        v_hash
        ||'|execution_proof=v2|'||ops.phase2_public_execution_proof_watermark()||'|'
        ||coalesce((
            SELECT string_agg(ops.phase2_hash_jsonb(to_jsonb(e)),'' ORDER BY e.evidence_id)
              FROM core.security_lifecycle_evidence e
             WHERE (e.evidence_type='FIRST_EVER_PUBLIC_TRADE' OR e.date_from<=p_date_to)
               AND ((e.source_document_date+1)::timestamp AT TIME ZONE 'Asia/Ho_Chi_Minh')
                   <=((p_date_to::timestamp+time '15:00') AT TIME ZONE 'Asia/Ho_Chi_Minh')
        ),'')
        ||'|liquidity_context=revision:'||v_context
        ||'|prior_membership='||v_prior_state
        ||'|listing_tenure=v2|'
        ||coalesce((
            SELECT string_agg(ops.phase2_hash_jsonb(to_jsonb(e)-'recorded_at'),'' ORDER BY e.event_id)
              FROM core.security_listing_events e
             WHERE e.available_at<=((p_date_to::timestamp+time '15:00') AT TIME ZONE 'Asia/Ho_Chi_Minh')
        ),'')
        ||'|listing_calendar='||coalesce((
            SELECT string_agg(ops.phase2_hash_jsonb(to_jsonb(c)),'' ORDER BY c.trade_date)
              FROM core.effective_trading_sessions c WHERE c.trade_date<=p_date_to
        ),'')
    );
END;
$phase2_label_base_hash_107$;

CREATE OR REPLACE FUNCTION ops.phase2_label_target_chunk_input_hash(
    p_date_from date,
    p_date_to date
)
RETURNS text
LANGUAGE plpgsql
VOLATILE
AS $phase2_label_input_hash_107$
DECLARE
    v_feature_hash text;
    v_execution_policy jsonb;
    v_dependency_revision text;
    v_input_hash text;
BEGIN
    v_feature_hash:=feat.phase2_feature_set_hash_v3();
    v_execution_policy:=ops.phase2_execution_weight_policy();
    v_dependency_revision:=ops.phase2_label_dependency_watermark();

    IF p_date_from IS NULL OR p_date_to IS NULL OR p_date_from>p_date_to THEN
        RETURN ops.phase2_hash_text(
            ops.phase2_label_target_chunk_base_input_hash(p_date_from,p_date_to)
            ||'|execution_policy='||v_execution_policy::text
            ||'|exact_limits_revision=v2|'||v_dependency_revision
        );
    END IF;

    IF current_setting('transaction_read_only')<>'on' THEN
        CREATE TEMP TABLE IF NOT EXISTS phase2_label_input_hash_tx_cache_107 (
            date_from date NOT NULL,
            date_to date NOT NULL,
            feature_set_hash text NOT NULL,
            execution_policy jsonb NOT NULL,
            dependency_revision text NOT NULL,
            input_hash text NOT NULL,
            PRIMARY KEY(date_from,date_to,feature_set_hash,execution_policy,dependency_revision)
        ) ON COMMIT DELETE ROWS;

        SELECT c.input_hash INTO v_input_hash
          FROM pg_temp.phase2_label_input_hash_tx_cache_107 c
         WHERE c.date_from=p_date_from
           AND c.date_to=p_date_to
           AND c.feature_set_hash=v_feature_hash
           AND c.execution_policy=v_execution_policy
           AND c.dependency_revision=v_dependency_revision;
        IF FOUND THEN
            RETURN v_input_hash;
        END IF;
    END IF;

    v_input_hash:=ops.phase2_hash_text(
        ops.phase2_label_target_chunk_base_input_hash(p_date_from,p_date_to)
        ||'|execution_policy='||v_execution_policy::text
        ||'|exact_limits_revision=v2|'||v_dependency_revision
    );

    IF current_setting('transaction_read_only')<>'on' THEN
        INSERT INTO pg_temp.phase2_label_input_hash_tx_cache_107(
            date_from,date_to,feature_set_hash,execution_policy,dependency_revision,input_hash
        ) VALUES (
            p_date_from,p_date_to,v_feature_hash,v_execution_policy,v_dependency_revision,v_input_hash
        )
        ON CONFLICT(date_from,date_to,feature_set_hash,execution_policy,dependency_revision)
        DO UPDATE SET input_hash=EXCLUDED.input_hash;
    END IF;

    RETURN v_input_hash;
END;
$phase2_label_input_hash_107$;

COMMENT ON FUNCTION ops.phase2_label_dependency_watermark() IS
    'Statement-level revision watermark for feature rows, raw label windows, linked exact price-limit observations, and mutable raw landing payloads.';
COMMENT ON FUNCTION ops.phase2_label_target_chunk_base_input_hash(date,date) IS
    'Versioned Phase 2 label manifest. Exact feature-context dependencies use a statement-level revision watermark; compact prior membership and lifecycle/calendar evidence remain content-hashed.';
COMMENT ON FUNCTION ops.phase2_label_target_chunk_input_hash(date,date) IS
    'Versioned Phase 2 label manifest with transaction-local caching keyed by feature set, execution policy, and dependency watermark; avoids serializing multi-year feature and price-limit panels.';

DO $phase2_label_watermark_assertions_107$
DECLARE
    v_base text:=pg_get_functiondef('ops.phase2_label_target_chunk_base_input_hash(date,date)'::regprocedure);
    v_input text:=pg_get_functiondef('ops.phase2_label_target_chunk_input_hash(date,date)'::regprocedure);
    v_triggers integer;
BEGIN
    IF position('ops.phase2_label_dependency_watermark()' IN v_base)=0
       OR position('FROM feat.features_daily f' IN v_base)>0
       OR position('ops.phase2_public_execution_proof_watermark()' IN v_base)=0 THEN
        RAISE EXCEPTION 'label base hash must use bounded feature and execution-proof revisions';
    END IF;
    IF position('phase2_label_input_hash_tx_cache_107' IN v_input)=0
       OR position('dependency_revision=v_dependency_revision' IN v_input)=0
       OR position('CROSS JOIN LATERAL' IN v_input)>0
       OR position('daily_price_limit_observations' IN v_input)>0
       OR position('used_limits' IN v_input)>0 THEN
        RAISE EXCEPTION 'label execution-evidence hash must use the revision watermark and bounded cache key';
    END IF;
    SELECT count(*) INTO v_triggers
      FROM pg_trigger t
     WHERE NOT t.tgisinternal
       AND t.tgname IN (
           'phase2_label_dependency_features_daily',
           'phase2_label_dependency_labels_daily',
           'phase2_label_dependency_price_limits',
           'phase2_label_dependency_raw_landings'
       );
    IF v_triggers<>4 THEN
        RAISE EXCEPTION 'label dependency revision triggers are incomplete: %',v_triggers;
    END IF;
END;
$phase2_label_watermark_assertions_107$;

COMMIT;
