-- No vendor calls; reclassify only when separately sourced lifecycle evidence exists.
\pset pager off
SELECT source_observation,derived_lifecycle_status, count(*) AS observations
FROM ops.zero_volume_lifecycle_status
GROUP BY source_observation,derived_lifecycle_status
ORDER BY derived_lifecycle_status;
