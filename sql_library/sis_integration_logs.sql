-- SIS Framework data integration logs: per-data-set summary and detail log lines
-- data_intgr_log can be large; always keep the date filter in place

-- © 2026 Blackboard Inc. All rights reserved.
-- This software is provided "as is" without warranty or support
-- jeff.kelley@blackboard.com 2026-10-30


-- ---------------------------------------------------------------------------
-- 1. Summary: one row per data set (feed file) processed by each integration
-- ---------------------------------------------------------------------------
WITH log_counts AS (
  SELECT
    data_intgr_pk1,
    data_set_uid,
    MIN(log_date) AS first_log_date,
    MAX(log_date) AS last_log_date,
    COUNT(*) FILTER (WHERE log_level = 3) AS error_count,
    COUNT(*) FILTER (WHERE log_level = 2) AS warning_count,
    COUNT(*) FILTER (WHERE log_level IN (0, 1)) AS info_debug_count
  FROM data_intgr_log
  WHERE log_date >= NOW() - INTERVAL '7 days'  -- adjust window as needed
  GROUP BY data_intgr_pk1, data_set_uid
)
SELECT
  di.name AS integration_name,
  di.type_handle,
  CASE di.integration_state
    WHEN 'A' THEN 'Active'
    WHEN 'I' THEN 'Inactive'
    WHEN 'L' THEN 'Log Only'
  END AS integration_state,
  lc.data_set_uid,
  ds.first_entry_dt AT TIME ZONE 'UTC' AT TIME ZONE 'America/New_York' AS data_set_started,  -- adjust time zone per institution
  ds.last_entry_dt  AT TIME ZONE 'UTC' AT TIME ZONE 'America/New_York' AS data_set_last_update,
  ds.completed_count,
  ds.queued_count,
  lc.error_count,
  lc.warning_count,
  lc.info_debug_count
FROM log_counts lc
LEFT JOIN data_intgr di
  ON di.pk1 = lc.data_intgr_pk1
LEFT JOIN data_intgr_data_set_status ds
  ON ds.data_intgr_pk1 = lc.data_intgr_pk1
  AND ds.data_set_uid = lc.data_set_uid
-- WHERE di.name = 'Nightly SIS Feed'  -- example: limit to one integration
ORDER BY lc.last_log_date DESC;


-- ---------------------------------------------------------------------------
-- 2. Detail: individual log lines (warnings and errors by default)
-- ---------------------------------------------------------------------------
SELECT
  dil.log_date AT TIME ZONE 'UTC' AT TIME ZONE 'America/New_York' AS log_date_local,  -- adjust time zone per institution
  di.name AS integration_name,
  dil.data_set_uid,
  CASE dil.log_level
    WHEN 0 THEN 'Debug'
    WHEN 1 THEN 'Info'
    WHEN 2 THEN 'Warning'
    WHEN 3 THEN 'Error'
  END AS log_level,
  dil.log_message
FROM data_intgr_log dil
LEFT JOIN data_intgr di
  ON di.pk1 = dil.data_intgr_pk1
WHERE dil.log_date >= NOW() - INTERVAL '7 days'  -- adjust window as needed
  AND dil.log_level >= 2  -- 2 = warnings and errors; 3 = errors only; 0 = everything
  -- AND di.name = 'Nightly SIS Feed'                      -- example: one integration
  -- AND dil.data_set_uid = '<data set uid from query 1>'  -- example: one feed file
  -- AND dil.log_message ILIKE '%jsmith%'                  -- example: search for a user/course id
ORDER BY dil.log_date DESC, dil.pk1 DESC;
