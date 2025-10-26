-- CTE: Maps each course to its subject (distance = 1, service_level = 'J')
WITH subject_map AS (
    SELECT
        ch.contained_crsmain_pk1 AS course_pk1,   -- The Course/Org being contained
        subj.course_id AS subject_id,             -- Subject's course_id
        subj.course_name AS subject_name          -- Subject's name
    FROM course_hierarchy ch
    JOIN course_main subj
        ON subj.pk1 = ch.container_crsmain_pk1
    WHERE ch.distance = 1
      AND subj.service_level = 'J'
),

-- CTE: Maps each course to its program (distance = 2, service_level = 'P')
program_map AS (
    SELECT
        ch.contained_crsmain_pk1 AS course_pk1,   -- The Course/Org being contained
        prog.course_id AS program_id,             -- Program's course_id
        prog.course_name AS program_name          -- Program's name
    FROM course_hierarchy ch
    JOIN course_main prog
        ON prog.pk1 = ch.container_crsmain_pk1
    WHERE ch.distance = 2
      AND prog.service_level = 'P'
)

-- Final query: Join course_main to both maps to enrich each course with its subject and program
SELECT
    prog.program_id,       -- Program course_id (if exists)
    prog.program_name,     -- Program name (if exists)
    subj.subject_id,       -- Subject course_id (if exists)
    subj.subject_name,     -- Subject name (if exists)
    cm.course_id,          -- Course/Org course_id
    cm.course_name         -- Course/Org name
FROM course_main cm
LEFT JOIN subject_map subj ON subj.course_pk1 = cm.pk1
LEFT JOIN program_map prog ON prog.course_pk1 = cm.pk1;