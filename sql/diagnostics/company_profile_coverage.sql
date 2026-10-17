-- Read-only Phase-1 coverage review. Flags indicate gaps in available
-- evidence, not inferred suspended/delisted or pre-listing statuses.
SELECT symbol,reported_listing_date,profile_job_state,first_traded_bar,
       bar_rows,source_zero_unverified,first_unverified_zero,
       last_unverified_zero,review_flags
FROM ops.company_profile_coverage_review
ORDER BY
    CASE WHEN 'ZERO_VOLUME_LIFECYCLE_UNVERIFIED'=ANY(review_flags) THEN 0 ELSE 1 END,
    source_zero_unverified DESC,symbol
LIMIT 100;

SELECT state,count(*) AS securities
FROM ops.company_profile_jobs GROUP BY state ORDER BY state;

SELECT batch_id,started_at,finished_at,max_calls,attempted,imported,
       missing_date,errors,skipped_existing,skipped_errors,
       skipped_unknown,deferred,last_error_type
FROM ops.company_profile_batch_runs ORDER BY batch_id DESC LIMIT 15;
