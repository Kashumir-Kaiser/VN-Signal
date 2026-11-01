\set ON_ERROR_STOP on
\pset pager off

-- Read-only post-build verifier for two independently recorded E5 label builds.
-- Invoke with explicit psql variables, e.g.:
--   psql -X -v ON_ERROR_STOP=1 \
--     -v build_a=phase2-e5-a -v build_b=phase2-e5-b \
--     -v date_from=2023-01-01 -v date_to=2023-12-31 \
--     -f docs/evidence/phase2/phase2_e5_repeatability_verify.sql "$DATABASE_URL"
-- The range must be a complete calendar year. Each build must have been run
-- with -ChunkMonths 1, creating one durable labels chunk per month. Run this
-- immediately after the second build, before another derived-target build.
-- No writes are made; the assertions and report run in a REPEATABLE READ,
-- READ ONLY transaction.

BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY;
SELECT set_config('vnsignal_e5.build_a', :'build_a', true),
       set_config('vnsignal_e5.build_b', :'build_b', true),
       set_config('vnsignal_e5.date_from', :'date_from', true),
       set_config('vnsignal_e5.date_to', :'date_to', true);

DO $verify$
DECLARE
    v_a text := current_setting('vnsignal_e5.build_a');
    v_b text := current_setting('vnsignal_e5.build_b');
    v_from date := current_setting('vnsignal_e5.date_from')::date;
    v_to date := current_setting('vnsignal_e5.date_to')::date;
    v_expected integer;
    v_build_rows integer;
    v_bad integer;
    v_current_hash text;
BEGIN
    IF v_a IS NULL OR v_b IS NULL OR v_a='' OR v_b='' OR v_a=v_b THEN
        RAISE EXCEPTION 'two distinct non-empty durable build IDs are required';
    END IF;
    IF v_from IS NULL OR v_to IS NULL
       OR v_from<>date_trunc('year',v_from)::date
       OR v_to<>(date_trunc('year',v_from)+interval '1 year'-interval '1 day')::date THEN
        RAISE EXCEPTION 'verification range must be exactly one calendar year';
    END IF;
    IF feat.phase2_feature_set_hash_v3() !~ '^[0-9a-f]{64}$' THEN
        RAISE EXCEPTION 'current V3 feature hash is unavailable';
    END IF;
    v_current_hash := feat.phase2_feature_set_hash_v3();

    WITH params AS (
        SELECT v_a AS build_a,v_b AS build_b,v_from AS date_from,v_to AS date_to
    ), months AS (
        SELECT g.month_start::date AS date_from,
               least((g.month_start+interval '1 month'-interval '1 day')::date,p.date_to) AS date_to
          FROM params p
          CROSS JOIN LATERAL generate_series(
              date_trunc('month',p.date_from)::timestamp,
              p.date_to::timestamp,
              interval '1 month') AS g(month_start)
    )
    SELECT count(*) INTO v_expected FROM months;
    IF v_expected<>12 THEN RAISE EXCEPTION 'expected 12 monthly chunks, found %',v_expected; END IF;
    SELECT count(*) INTO v_build_rows FROM ops.feature_chunks c
     WHERE c.build_id IN (v_a,v_b) AND c.stage='labels'
       AND c.date_from>=v_from AND c.date_to<=v_to;
    IF v_build_rows<>24 THEN
        RAISE EXCEPTION 'expected exactly 24 durable monthly label-chunk records, found %',v_build_rows;
    END IF;

    WITH params AS (
        SELECT v_a AS build_a,v_b AS build_b,v_from AS date_from,v_to AS date_to
    ), months AS (
        SELECT g.month_start::date AS date_from,
               least((g.month_start+interval '1 month'-interval '1 day')::date,p.date_to) AS date_to
          FROM params p
          CROSS JOIN LATERAL generate_series(
              date_trunc('month',p.date_from)::timestamp,
              p.date_to::timestamp,
              interval '1 month') AS g(month_start)
    ), paired AS (
        SELECT m.*,
               a.chunk_key AS key_a,a.status AS status_a,a.input_sha256 AS input_a,a.output_sha256 AS output_a,
               a.rows AS rows_a,a.execution_weight_policy AS policy_a,
               b.chunk_key AS key_b,b.status AS status_b,b.input_sha256 AS input_b,b.output_sha256 AS output_b,
               b.rows AS rows_b,b.execution_weight_policy AS policy_b,
               to_char(m.date_from,'YYYYMMDD')||'-'||to_char(m.date_to,'YYYYMMDD') AS chunk_key
          FROM months m
          LEFT JOIN ops.feature_chunks a
            ON a.build_id=v_a AND a.stage='labels' AND a.date_from=m.date_from AND a.date_to=m.date_to
          LEFT JOIN ops.feature_chunks b
            ON b.build_id=v_b AND b.stage='labels' AND b.date_from=m.date_from AND b.date_to=m.date_to
    )
    SELECT count(*) FILTER (
        WHERE key_a IS DISTINCT FROM chunk_key OR key_b IS DISTINCT FROM chunk_key
           OR status_a IS DISTINCT FROM 'done' OR status_b IS DISTINCT FROM 'done'
           OR input_a IS NULL OR input_b IS NULL OR output_a IS NULL OR output_b IS NULL
           OR input_a IS DISTINCT FROM input_b OR output_a IS DISTINCT FROM output_b
           OR rows_a IS NULL OR rows_b IS NULL OR rows_a IS DISTINCT FROM rows_b
           OR policy_a IS NULL OR policy_b IS NULL OR policy_a IS DISTINCT FROM policy_b
           OR NOT EXISTS (
               SELECT 1 FROM ops.step_runs r
                WHERE r.build_id=v_a AND r.stage='labels' AND r.chunk_key=paired.chunk_key
                  AND r.status='done' AND r.input_sha256=paired.input_a
                  AND r.output_sha256=paired.output_a AND r.rows=paired.rows_a)
           OR NOT EXISTS (
               SELECT 1 FROM ops.step_runs r
                WHERE r.build_id=v_b AND r.stage='labels' AND r.chunk_key=paired.chunk_key
                  AND r.status='done' AND r.input_sha256=paired.input_b
                  AND r.output_sha256=paired.output_b AND r.rows=paired.rows_b)
    ) INTO v_bad
      FROM paired;
    IF v_bad<>0 THEN
        RAISE EXCEPTION '% monthly chunks are missing, failed, stale-policy, or hash/row mismatched',v_bad;
    END IF;

-- Migration 090 stamps the actual label runner build ID on each derived-target
-- attempt. Resumed builds can have earlier, now-stale attempts under the same
-- ID. Identify the current attempt by the durable label-chunk input hash and
-- current target content hash, not by recency or by assuming there is only one
-- historical attempt.
WITH months AS (
        SELECT g.month_start::date AS date_from,
               least((g.month_start+interval '1 month'-interval '1 day')::date,v_to) AS date_to
          FROM LATERAL generate_series(
              date_trunc('month',v_from)::timestamp,v_to::timestamp,interval '1 month') AS g(month_start)
), base AS MATERIALIZED (
    SELECT m.date_from,m.date_to,
           a.input_sha256 AS expected_input_a,b.input_sha256 AS expected_input_b,
           ops.phase2_label_targets_chunk_hash(m.date_from,m.date_to) AS current_target_hash
      FROM months m
      JOIN ops.feature_chunks a
        ON a.build_id=v_a AND a.stage='labels' AND a.date_from=m.date_from AND a.date_to=m.date_to
      JOIN ops.feature_chunks b
        ON b.build_id=v_b AND b.stage='labels' AND b.date_from=m.date_from AND b.date_to=m.date_to
), paired AS (
    SELECT base.*,
           ta.attempts AS attempts_a,ta.matching_attempts AS matching_attempts_a,
           ta.matching_rows AS rows_a,ta.matching_output AS output_a,
           tb.attempts AS attempts_b,tb.matching_attempts AS matching_attempts_b,
           tb.matching_rows AS rows_b,tb.matching_output AS output_b
      FROM base
      CROSS JOIN LATERAL (
          SELECT count(*) FILTER(WHERE x.status='done')::integer AS attempts,
                 count(*) FILTER(WHERE x.status='done'
                   AND x.input_hash=base.expected_input_a
                   AND x.output_hash=base.current_target_hash)::integer AS matching_attempts,
                 min(x.output_hash) FILTER(WHERE x.status='done'
                   AND x.input_hash=base.expected_input_a
                   AND x.output_hash=base.current_target_hash) AS matching_output,
                 min(x.rows) FILTER(WHERE x.status='done'
                   AND x.input_hash=base.expected_input_a
                   AND x.output_hash=base.current_target_hash) AS matching_rows
            FROM ops.phase2_label_target_chunk_runs x
           WHERE x.label_build_id=v_a AND x.date_from=base.date_from AND x.date_to=base.date_to
      ) ta
      CROSS JOIN LATERAL (
          SELECT count(*) FILTER(WHERE x.status='done')::integer AS attempts,
                 count(*) FILTER(WHERE x.status='done'
                   AND x.input_hash=base.expected_input_b
                   AND x.output_hash=base.current_target_hash)::integer AS matching_attempts,
                 min(x.output_hash) FILTER(WHERE x.status='done'
                   AND x.input_hash=base.expected_input_b
                   AND x.output_hash=base.current_target_hash) AS matching_output,
                 min(x.rows) FILTER(WHERE x.status='done'
                   AND x.input_hash=base.expected_input_b
                   AND x.output_hash=base.current_target_hash) AS matching_rows
            FROM ops.phase2_label_target_chunk_runs x
           WHERE x.label_build_id=v_b AND x.date_from=base.date_from AND x.date_to=base.date_to
      ) tb
)
SELECT count(*) FILTER (
    WHERE attempts_a<1 OR attempts_b<1
       OR matching_attempts_a<>1 OR matching_attempts_b<>1
       OR output_a IS NULL OR output_b IS NULL OR output_a IS DISTINCT FROM output_b
       OR rows_a IS NULL OR rows_b IS NULL OR rows_a IS DISTINCT FROM rows_b
       OR output_a IS DISTINCT FROM current_target_hash
) INTO v_bad FROM paired;
    IF v_bad<>0 THEN
        RAISE EXCEPTION '% months do not have exactly one current-content-derived-target attempt per label build ID with equal hashes and row counts',v_bad;
    END IF;

    IF EXISTS (
        SELECT 1 FROM feat.labels_daily l
         WHERE l.signal_date BETWEEN v_from AND v_to
           AND l.label_version='close-next-open-v1'
           AND l.feature_set_hash IS DISTINCT FROM v_current_hash
    ) THEN
        RAISE EXCEPTION 'the year contains label rows from a stale V3 feature hash';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM feat.labels_daily l
         WHERE l.signal_date BETWEEN v_from AND v_to
           AND l.label_version='close-next-open-v1'
           AND l.feature_set_hash=v_current_hash
    ) THEN
        RAISE EXCEPTION 'no current-hash labels exist in the requested year';
    END IF;
    IF EXISTS (
        SELECT 1 FROM feat.phase2_label_targets_v3 t
         WHERE t.signal_date BETWEEN v_from AND v_to
           AND t.feature_set_hash IS DISTINCT FROM v_current_hash
    ) THEN
        RAISE EXCEPTION 'the year contains derived targets from a stale V3 feature hash';
    END IF;
END;
$verify$;

-- Canonical whole-year content digest: the production hash helpers exclude
-- labels_daily.computed_at and target built_at. The durable year digest is a
-- deterministic ordered Merkle-style rollup of the 12 per-month runner output
-- hashes, each of which combines canonical labels and target hashes.
WITH params AS (
    SELECT current_setting('vnsignal_e5.build_a') AS build_a,
           current_setting('vnsignal_e5.build_b') AS build_b,
           current_setting('vnsignal_e5.date_from')::date AS date_from,
           current_setting('vnsignal_e5.date_to')::date AS date_to
), months AS (
    SELECT g.month_start::date AS date_from,
           least((g.month_start+interval '1 month'-interval '1 day')::date,p.date_to) AS date_to,
           p.build_a,p.build_b
      FROM params p
      CROSS JOIN LATERAL generate_series(
          date_trunc('month',p.date_from)::timestamp,p.date_to::timestamp,interval '1 month') AS g(month_start)
), pair_hashes AS (
    SELECT m.date_from,m.date_to,a.input_sha256 AS input_a,b.input_sha256 AS input_b,
           a.output_sha256 AS output_a,b.output_sha256 AS output_b,
           a.execution_weight_policy AS policy_a,b.execution_weight_policy AS policy_b
      FROM months m
      JOIN ops.feature_chunks a
        ON a.build_id=m.build_a AND a.stage='labels' AND a.date_from=m.date_from AND a.date_to=m.date_to
      JOIN ops.feature_chunks b
        ON b.build_id=m.build_b AND b.stage='labels' AND b.date_from=m.date_from AND b.date_to=m.date_to
)
SELECT current_setting('vnsignal_e5.build_a') AS build_a,
       current_setting('vnsignal_e5.build_b') AS build_b,
       current_setting('vnsignal_e5.date_from') AS date_from,
       current_setting('vnsignal_e5.date_to') AS date_to,
       feat.phase2_feature_set_hash_v3() AS current_feature_hash,
       count(*) AS verified_month_chunks,
       count(*) FILTER (WHERE ops.phase2_label_targets_chunk_hash(date_from,date_to) IS NOT NULL) AS months_with_target_hash,
       ops.phase2_hash_text(
           'phase2-e5-year-chunks-v1|'||string_agg(date_from::text||':'||date_to::text||':'||output_a,
                                                    '|' ORDER BY date_from)
       ) AS durable_year_output_hash_a,
       ops.phase2_hash_text(
           'phase2-e5-year-chunks-v1|'||string_agg(date_from::text||':'||date_to::text||':'||output_b,
                                                    '|' ORDER BY date_from)
       ) AS durable_year_output_hash_b,
       ops.phase2_hash_text(
           'phase2-e5-year-canonical-v1|'||
           ops.phase2_chunk_output_hash('labels',
               current_setting('vnsignal_e5.date_from')::date,
               current_setting('vnsignal_e5.date_to')::date)||'|'||
           ops.phase2_label_targets_chunk_hash(
               current_setting('vnsignal_e5.date_from')::date,
               current_setting('vnsignal_e5.date_to')::date)
       ) AS canonical_full_year_content_hash,
       jsonb_agg(policy_a ORDER BY date_from)->0 AS effective_execution_policy
  FROM pair_hashes;

ROLLBACK;
