-- AACSB-tagged question grades by student, for assurance-of-learning reporting.
-- jeff.kelley@blackboard.com 2026-08-12
-- No warranty or support.
--
-- Contributed by Chris Bray, Director of Academic Technology Services, cbray@uark.edu

-- Walks the qti_result_data tree recursively rather than assuming a fixed
-- depth (root -> section -> item). Tests with sub-sections, random blocks,
-- or question sets nest items deeper than two levels; a fixed two-hop join
-- silently drops those questions instead of erroring, which is dangerous
-- for an accreditation report. Identifying item-level nodes by
-- qti_asi_data.bbmd_asi_type = 3 (Item) is reliable regardless of depth.
--
-- qti_asi_data.title and qti_asi_data.description are both unreliable for
-- getting at question wording, and which one (if either) has real content
-- varies by how the test was authored/imported - check a sample from your
-- own course before trusting either. description is capped at 100 chars
-- regardless, so long questions truncate either way. The full question text
-- lives in qti_asi_data.data as a QTI XML blob and requires
-- application-layer parsing to extract in full.
--
-- The category name used to tag AACSB-aligned questions varies by
-- institution (may be a Topic/Keyword category_type, not literally
-- category = 'AACSB') - adjust the filter below to match your course's
-- actual category setup.

WITH RECURSIVE base AS (
    SELECT
        cm.pk1                  AS crsmain_pk1,
        cm.course_id,
        u.user_id,
        gm.title                 AS test_name,
        a.qti_result_data_pk1
    FROM course_main cm
    JOIN gradebook_main gm  ON gm.crsmain_pk1 = cm.pk1
    JOIN gradebook_grade gg ON gg.gradebook_main_pk1 = gm.pk1
    JOIN course_users cu    ON cu.pk1 = gg.course_users_pk1
    JOIN users u             ON u.pk1 = cu.users_pk1
    JOIN attempt a           ON a.pk1 = gg.last_attempt_pk1
    WHERE cm.course_id LIKE '2025_FALL_ACCT_20103_%'  -- wildcard course selector, adjust per institution
      AND a.qti_result_data_pk1 IS NOT NULL
),
qrd_tree AS (
    -- seed: the root QTI result node for each attempt
    SELECT
        b.course_id, b.user_id, b.test_name, b.crsmain_pk1,
        qrd.pk1 AS qrd_pk1, qrd.qti_asi_data_pk1, qrd.bbmd_grade
    FROM base b
    JOIN qti_result_data qrd ON qrd.pk1 = b.qti_result_data_pk1

    UNION ALL

    -- recurse: step down through sections/sub-sections/blocks to whatever depth exists
    SELECT
        t.course_id, t.user_id, t.test_name, t.crsmain_pk1,
        child.pk1, child.qti_asi_data_pk1, child.bbmd_grade
    FROM qrd_tree t
    JOIN qti_result_data child ON child.parent_pk1 = t.qrd_pk1
)
SELECT
    t.user_id     AS "User ID",
    t.course_id   AS "Course ID",
    t.test_name   AS "Test Name",
    COALESCE(NULLIF(TRIM(qad.title), ''), qad.description) AS "Question",
    t.bbmd_grade  AS "Grade",
    c.category    AS "Tag"
FROM qrd_tree t
JOIN qti_asi_data qad  ON qad.pk1 = t.qti_asi_data_pk1
                       AND qad.bbmd_asi_type = 3  -- 3 = Item; excludes assessment/section/summary nodes
JOIN item_category ic  ON ic.qti_asi_data_pk1 = qad.pk1
JOIN category c        ON c.pk1 = ic.category_pk1
                       AND c.crsmain_pk1 = t.crsmain_pk1
WHERE c.category = 'AACSB'  -- adjust to match your institution's actual category name/type
ORDER BY t.user_id, t.test_name, "Question";
