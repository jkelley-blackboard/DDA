-- Users tagged to a "demo" data source who have zero course enrollments.
-- jeff.kelley@blackboard.com 2026-09-12
-- No warranty or support.
--
-- "Demo" is identified by data_source.batch_uid, not a fixed value - naming for
-- demo/sandbox data sources varies by institution (e.g. 'DEMO', 'DEMO_BATCH',
-- 'SANDBOX'). Adjust the pattern below to match your environment; check
-- data_source.batch_uid/description first if you're not sure what it's called.
--
-- "No enrollments" means no row in course_users at all (any role, any
-- row_status) - add a course_users.row_status = 0 filter to the NOT EXISTS
-- clause below if you only want to exclude users with an active enrollment.

WITH my_constants AS (
  SELECT 'DEMO%'::text AS demo_batch_uid_pattern  -- adjust to match your demo data source's batch_uid
)
SELECT
  uu.pk1,
  uu.email,
  uu.user_id,
  uu.last_login_date
FROM users uu
JOIN data_source ds ON ds.pk1 = uu.data_src_pk1
WHERE ds.batch_uid ILIKE (SELECT demo_batch_uid_pattern FROM my_constants)
  AND uu.row_status = 0
  AND NOT EXISTS (
    SELECT 1
    FROM course_users cu
    WHERE cu.users_pk1 = uu.pk1
  )
ORDER BY uu.user_id;
