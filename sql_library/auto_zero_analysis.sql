-- Check where courses have auto-zero enabled or have grades that were auto-zeroed
-- jeff.kelley@anthology.com 2025-05-24
-- No warranty or support

WITH autoZeros AS (
  SELECT 
    gm.crsmain_pk1,
    COUNT(gg.pk1) AS grade_count
  FROM gradebook_grade gg
  JOIN gradebook_main gm ON gm.pk1 = gg.gradebook_main_pk1
  WHERE gg.automatic_zero = 'Y'
  GROUP BY gm.crsmain_pk1
)
SELECT
  cm.course_id,
  gbs.enable_automatic_zero AS auto_zero_enabled,
  COALESCE(az.grade_count, 0) AS auto_zero_grades
FROM gradebook_settings gbs
JOIN course_main cm ON cm.pk1 = gbs.crsmain_pk1
LEFT JOIN autoZeros az ON az.crsmain_pk1 = cm.pk1
WHERE gbs.enable_automatic_zero = 'Y' 
  OR az.grade_count > 0
ORDER BY cm.course_id;
