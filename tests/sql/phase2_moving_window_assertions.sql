-- Independent exactness checks for the V2 block-prefix/suffix 250-session
-- extrema. Exercises nulls, large levels, small variation and episode resets.
-- No market or fixture data is read or changed.
BEGIN;
DO $assert$
DECLARE
    mismatch_count bigint;
BEGIN
    WITH samples AS MATERIALIZED (
        SELECT symbol_id,n,
               CASE WHEN n IN (301,602) THEN NULL ELSE
                    CASE WHEN symbol_id=1 THEN 1000000.0+sin(n::double precision)*0.02
                         WHEN symbol_id=2 THEN sin(n::double precision)*1e-6+(n%7)*1e-9
                         WHEN symbol_id=3 THEN NULL::double precision
                         ELSE CASE WHEN n=1 THEN 17.0 ELSE NULL::double precision END END
               END AS high_value,
               CASE WHEN n IN (301,602) OR n%23=0 THEN NULL ELSE
                    CASE WHEN symbol_id=1 THEN 1000000.0+cos(n::double precision)*0.02
                         WHEN symbol_id=2 THEN cos(n::double precision)*1e-6-(n%5)*1e-9
                         WHEN symbol_id=3 THEN NULL::double precision
                         ELSE CASE WHEN n=1 THEN -17.0 ELSE NULL::double precision END END
               END AS low_value
        FROM generate_series(1,4) symbols(symbol_id)
        CROSS JOIN generate_series(1,900) rows(n)
    ), episode_marked AS (
        SELECT s.*,
               sum(CASE WHEN n IN (301,602) THEN 1 ELSE 0 END)
                 OVER(PARTITION BY symbol_id ORDER BY n ROWS UNBOUNDED PRECEDING) AS episode
        FROM samples s
    ), marked AS (
        SELECT e.*,row_number() OVER(PARTITION BY symbol_id,episode ORDER BY n)-1 AS episode_row
        FROM episode_marked e
    ), blocks AS MATERIALIZED (
        SELECT m.*,(episode_row/250)::bigint AS block_no,
               max(high_value) OVER(PARTITION BY symbol_id,episode,(episode_row/250) ORDER BY episode_row ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS high_prefix,
               max(high_value) OVER(PARTITION BY symbol_id,episode,(episode_row/250) ORDER BY episode_row ROWS BETWEEN CURRENT ROW AND UNBOUNDED FOLLOWING) AS high_suffix,
               min(low_value) OVER(PARTITION BY symbol_id,episode,(episode_row/250) ORDER BY episode_row ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS low_prefix,
               min(low_value) OVER(PARTITION BY symbol_id,episode,(episode_row/250) ORDER BY episode_row ROWS BETWEEN CURRENT ROW AND UNBOUNDED FOLLOWING) AS low_suffix
        FROM marked m
    ), lagged AS (
        SELECT b.*,
               lag(high_suffix,249) OVER(PARTITION BY symbol_id,episode ORDER BY episode_row) AS high_suffix_start,
               lag(low_suffix,249) OVER(PARTITION BY symbol_id,episode ORDER BY episode_row) AS low_suffix_start
        FROM blocks b
    ), actual AS (
        SELECT l.*,
               CASE WHEN episode_row<249 OR block_no=((episode_row-249)/250) THEN high_prefix
                    ELSE greatest(high_prefix,high_suffix_start) END AS high250_new,
               CASE WHEN episode_row<249 OR block_no=((episode_row-249)/250) THEN low_prefix
                    ELSE least(low_prefix,low_suffix_start) END AS low250_new,
               max(high_value) OVER(PARTITION BY symbol_id,episode ORDER BY episode_row ROWS BETWEEN 249 PRECEDING AND CURRENT ROW) AS high250_ref,
               min(low_value) OVER(PARTITION BY symbol_id,episode ORDER BY episode_row ROWS BETWEEN 249 PRECEDING AND CURRENT ROW) AS low250_ref
        FROM lagged l
    )
    SELECT count(*) INTO mismatch_count
    FROM actual
    WHERE high250_new IS DISTINCT FROM high250_ref OR low250_new IS DISTINCT FROM low250_ref;
    IF mismatch_count<>0 THEN
        RAISE EXCEPTION 'block prefix/suffix extrema differ from direct 250-row frame at % observations',mismatch_count;
    END IF;
END;
$assert$;
ROLLBACK;
