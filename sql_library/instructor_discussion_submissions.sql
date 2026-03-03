/* 
===============================================================================
Instructor Discussion Forum Submissions

Description:
Returns instructor discussion forum submissions for a specific course 
and date range.

Filters:
  • COURSE.COURSE_NUMBER = {course_number}
  • SUBMISSION.ITEM_TYPE = 'DISCUSSION_FORUM'
  • SUBMISSION.SUBMITTED_TIME between {start_date} and {end_date}
  • PERSON_COURSE.COURSE_ROLE = 'I' (Instructor)

Surfaces:
  • Blackboard username (PERSON.STAGE:user_id)
  • Course number
  • Course item name
  • Submission name
  • Submission timestamp
  • Submission size
  • Parameter start/end dates (for validation in result set)

Replace placeholders:
  {start_date}
  {end_date}
  {course_number}
===============================================================================
*/

WITH parameters AS (
    SELECT 
        TO_TIMESTAMP('{start_date}') AS start_date,
        TO_TIMESTAMP('{end_date}')   AS end_date,
        '{course_number}'            AS course_number
)

SELECT
    p.stage:user_id::string        AS username,
    c.course_number,
    params.start_date,
    params.end_date,
    ci.name                        AS item_name,
    s.name                         AS submission_name,
    s.submitted_time,
    s.submission_size
FROM CDM_LMS.SUBMISSION s
INNER JOIN CDM_LMS.PERSON_COURSE pc
    ON pc.id = s.person_course_id
INNER JOIN CDM_LMS.PERSON p
    ON p.id = pc.person_id
INNER JOIN CDM_LMS.COURSE c
    ON c.id = pc.course_id
INNER JOIN CDM_LMS.COURSE_ITEM ci
    ON ci.id = s.course_item_id
CROSS JOIN parameters params
WHERE pc.course_role = 'I'
  AND s.item_type = 'DISCUSSION_FORUM'
  AND c.course_number = params.course_number
  AND s.submitted_time 
        BETWEEN params.start_date AND params.end_date
ORDER BY s.submitted_time DESC;