-- grade status count by course
-- jeff.kelley@blackboard.com   without support or warranty
-- 15 June 2022

WITH attempt_summary_raw AS (
  SELECT
    gradebook_grade_pk1,
    COUNT(pk1) AS total_cnt,
    SUM(CASE WHEN status = 7 THEN 1 ELSE 0 END) AS posted_cnt,
    SUM(CASE WHEN status = 6 AND ready_to_post_ind = 'Y' THEN 1 ELSE 0 END) AS unposted_cnt,
    SUM(CASE WHEN status = 6 AND ready_to_post_ind != 'Y' THEN 1 ELSE 0 END) AS ungraded_cnt
  FROM attempt
  GROUP BY gradebook_grade_pk1
),

attempt_summary AS (
  SELECT
    gradebook_grade_pk1,
    CASE
      WHEN posted_cnt > 0 THEN 'posted'
      WHEN posted_cnt = 0 AND unposted_cnt > 0 THEN 'unposted'
      ELSE 'ungraded'
    END AS astatus
  FROM attempt_summary_raw
),

grade_status AS (
  SELECT
    cm.course_id,
    cm.course_name,
    CASE
      WHEN gg.automatic_zero = 'Y'             THEN 'automatic-zero'
      WHEN gg.manual_grade IS NOT NULL         THEN 'manual-posted'
      WHEN gg.pending_manual_grade IS NOT NULL THEN 'manual-unposted'
      WHEN attsum.astatus IS NULL              THEN 'nothing-to-grade'
      ELSE CONCAT('attempted-', attsum.astatus)
    END AS grade_status
  FROM gradebook_grade gg
    JOIN gradebook_main gm  ON gm.pk1 = gg.gradebook_main_pk1
    JOIN course_main cm     ON cm.pk1 = gm.crsmain_pk1
    JOIN course_users cu    ON cu.pk1 = gg.course_users_pk1
    LEFT JOIN attempt_summary attsum ON attsum.gradebook_grade_pk1 = gg.pk1
  WHERE gm.deleted_ind = 'N'
    AND gm.visible_in_book_ind = 'Y'
    AND cm.course_id ILIKE '%kelley%'   -- wildcard course selector
)

SELECT
  course_id,
  course_name,
  COUNT(*)                                                                         AS total,
  SUM(CASE WHEN grade_status = 'automatic-zero'   THEN 1 ELSE 0 END)              AS automatic_zero,
  SUM(CASE WHEN grade_status = 'manual-posted'    THEN 1 ELSE 0 END)              AS manual_posted,
  SUM(CASE WHEN grade_status = 'manual-unposted'  THEN 1 ELSE 0 END)              AS manual_unposted,
  SUM(CASE WHEN grade_status = 'nothing-to-grade' THEN 1 ELSE 0 END)              AS nothing_to_grade,
  SUM(CASE WHEN grade_status = 'attempted-posted'   THEN 1 ELSE 0 END)            AS attempted_posted,
  SUM(CASE WHEN grade_status = 'attempted-unposted' THEN 1 ELSE 0 END)            AS attempted_unposted,
  SUM(CASE WHEN grade_status = 'attempted-ungraded' THEN 1 ELSE 0 END)            AS attempted_ungraded
FROM grade_status
GROUP BY
  course_id,
  course_name
ORDER BY
  course_id;