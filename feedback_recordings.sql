-- gets links to all feedback videos
-- jeff.kelley@anthology.com  2025-05-25
-- no warranty or support
WITH feedbackVideos AS (
    SELECT
        pk1,
        gradebook_main_pk1,
        username AS student,
        modifier_username AS instructor,
        regexp_split_to_table(
            array_to_string(regexp_matches(for_student_comments, '&quot;video_uuid&quot;:&quot;([0-9a-f\-]+)&quot;', 'g'), ';'),
            ';') AS videouuid,
        'for_student' AS comment_type
    FROM gradebook_log
    WHERE for_student_comments LIKE '%data-bbtype="collab_video"%'
    
    UNION ALL
    
    SELECT
        pk1,
        gradebook_main_pk1,
        username AS student,
        modifier_username AS instructor,
        regexp_split_to_table(
            array_to_string(regexp_matches(instructor_comments, '&quot;video_uuid&quot;:&quot;([0-9a-f\-]+)&quot;', 'g'), ';'),
            ';') AS videouuid,
        'grader_notes' AS comment_type
    FROM gradebook_log
    WHERE instructor_comments LIKE '%data-bbtype="collab_video"%'
)
SELECT
    cm.course_id,
    gm.title AS assignment_name,
    fv.student,
    fv.instructor,
    fv.comment_type,
    CONCAT(
        (SELECT registry_value FROM system_registry WHERE registry_key = 'BBRL.autodetected_url'),
        '/webapps/videointegration/view/play?course_id=_', cm.pk1::text, '_1&videoUuid=', fv.videouuid) AS video_url
FROM feedbackVideos fv
JOIN gradebook_main gm ON gm.pk1 = fv.gradebook_main_pk1
JOIN course_main cm ON cm.pk1 = gm.crsmain_pk1
WHERE cm.course_id ILIKE '%%';
