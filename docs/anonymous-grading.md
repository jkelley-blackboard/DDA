---
meta-viewport: width=device-width,initial-scale=1
title: Anonymous Grading
---

# Anonymous Grading

[← Back to Overview](index.md)

This page explains where anonymous grading shows up in DDA for Ultra courses, including the **Reveal student identity for anonymous assessments** feature released in September 2026. It covers which tables hold the evidence, how that evidence moves as an assessment goes from anonymous grading to posted grades, and starter queries.

> **Treat this page as directional guidance, not a specification.**
> Blackboard does not document how anonymous grading is stored in the database. Everything here comes from the schema documentation plus a small, controlled test on a single demo environment, using one assignment and one grader. It describes behaviour we observed, not guaranteed rules.
>
> - Behaviour may differ for group assignments, tests, delegated grading, or other configurations we did not test.
> - Behaviour may change in future releases without notice.
> - Validate any query against your own data before relying on it for reporting, audits, or decisions about individuals.

---

## The Short Version

- **Assessments that are anonymous right now** are flagged on `gradebook_main.anonymous_grading_ind`.
- **Posting grades clears that flag.** Once names are revealed at posting, the column no longer records that it was ever anonymous. The evidence moves to `attempt` and `gradebook_log`.
- **Each identity reveal is logged** in `gradebook_log` with `event_key = 'reveal_identity'`, including who revealed the name and the reason they entered.
- **Viewing a name is not the same as grading with it.** A submission is only recorded as graded non-anonymously if a grade was saved while the student's name was visible.

---

## Where Anonymity Lives in the Schema

All of these tables are in the gradebook area of the schema. The right-hand column describes what we observed in Ultra courses, which sometimes differs from the schema description.

| Table | Column | What it tells you (as observed in Ultra) |
|---|---|---|
| `gradebook_main` | `anonymous_grading_ind` | `Y` while the column is being graded anonymously. Changes to `N` when grades are posted. |
| `gradebook_main` | `delegated_grading_ind` | `Y` when delegated grading is also enabled. |
| `attempt_staged_grading` | `pending_anonymous_ind` | `Y` on each submission's provisional grade while grading is anonymous. These rows are removed when grades are posted. |
| `attempt_staged_grading` | `graded_anonymously_ind` | `N` if a grade was saved while the student's name was revealed. Otherwise `Y`. |
| `attempt` | `graded_anonymously_ind` | Set when grades are posted. `Y` = graded anonymously, `N` = graded while the name was visible. |
| `gradebook_log` | `event_key` | Grade History event type. Look for `reveal_identity` and `anonymity_lifted`. |
| `gradebook_log` | `instructor_comments` | On `reveal_identity` rows, holds the reason the grader entered. |

Group assignments have matching columns in `group_attempt` and `group_attempt_staged_grading`. We have not tested whether they behave the same way.

### Columns that look relevant but are not

- **`gradebook_main.permanent_anonymous_ind`** marks anonymous surveys and forms, not anonymously graded assessments.
- **`gradebook_main.anon_grading_rel_crit`** and **`anon_grading_release_date`** hold name-release settings from Original courses. Ultra does not appear to set them. You may still see them on Ultra courses that were copied or converted from Original.
- **`gradebook_main.has_anonymous_submissions_ind`** is rarely populated and is not a reliable history flag.
- **`gradebook_log.graded_anonymously_ind`** is not a reliable way to spot reveals. Ordinary anonymous grade saves write one log row with `N` and another with `Y`.

---

## Reveal Student Identity

This Ultra feature lets an authorized grader temporarily see one student's name on an anonymously graded submission in Flexible Grading. The grader must give a reason. See the Blackboard Help topic *Grade Anonymously* for how the feature works.

It is off by default. In DDA, the two switches appear as:

| Setting | Where it shows in DDA |
|---|---|
| Tool: *Reveal student identity for anonymous assessment* | `application` row where `application = 'bb-reveal-student-identity'`. An `enabled_mask` of `0` means off. |
| Privilege: *Reveal student identity for anonymous assessment* | `entitlement_uid = 'course.gradebook-reveal-student-identity.EXECUTE'`, assigned through `course_roles_entitlement` and `system_roles_entitlement` |

### What gets recorded

| Action | `gradebook_log` | Submission's anonymity flag |
|---|---|---|
| Reveal a name | One `reveal_identity` row: student, grader, time, and reason | No change |
| Hide the name again | Nothing logged | No change |
| Save a grade while the name is visible | The usual grade-save rows, which look the same as anonymous grading | Changes to `N` and stays `N`, even if the name is hidden again |
| Post grades | One `anonymity_lifted` row for every student in the column, plus a `post_grade` row per posted grade | Final value written to `attempt.graded_anonymously_ind` |

A few details about `reveal_identity` rows:

- `attempt_pk1` is empty. To connect a reveal to a submission, join on `gradebook_main_pk1` and `user_pk1`.
- `anonymizing_id` holds the gradebook column's `pk1`, not an attempt `pk1` as the schema description suggests.
- The reason is free text entered by the grader, and the row also records the grader's IP address. Handle these rows with the same care as any other grading audit data.

---

## Which Source Answers Which Question

| Question | Before grades are posted | After grades are posted |
|---|---|---|
| Which assessments use anonymous grading? | `gradebook_main.anonymous_grading_ind = 'Y'` | `anonymity_lifted` rows in `gradebook_log` for that column |
| Which submissions were graded anonymously? | `attempt_staged_grading.graded_anonymously_ind = 'Y'` | `attempt.graded_anonymously_ind = 'Y'` |
| Which grades were saved with the student's name visible? | `attempt_staged_grading.graded_anonymously_ind = 'N'` | `attempt.graded_anonymously_ind = 'N'` on a column that has `anonymity_lifted` rows |
| Who viewed a student's name, when, and why? | `reveal_identity` rows in `gradebook_log` | Same |

**About older data:** the `reveal_identity` and `anonymity_lifted` events only exist from the September 2026 release onward. An Ultra assessment whose grades were posted before then may leave little trace beyond `attempt.graded_anonymously_ind = 'Y'`. Also note that `attempt.graded_anonymously_ind = 'N'` is the normal value on ordinary, non-anonymous submissions. It only means "graded with the name visible" on a column you already know was anonymous.

---

## Starter Queries

These are starting points. Adjust the date ranges for your institution, and check the results against what you see in the Blackboard interface. `gradebook_log` can be large, so keep a date filter on it where you can.

### Identity reveals

```sql
-- Every identity reveal, with the grader and their reason.
SELECT
  gl.date_logged,
  cm.course_id,
  gm.title,
  gl.username            AS student,
  gl.modifier_username   AS revealed_by,
  gl.instructor_comments AS reason
FROM gradebook_log gl
JOIN gradebook_main gm ON gm.pk1 = gl.gradebook_main_pk1
JOIN course_main cm    ON cm.pk1 = gm.crsmain_pk1
WHERE gl.event_key = 'reveal_identity'
  AND gl.date_logged >= now() - interval '180 days'   -- adjust range per institution
ORDER BY gl.date_logged DESC;
```

### Anonymous assessments, current and released

```sql
-- Ultra columns that are anonymous now, or whose anonymity was lifted when grades were posted.
SELECT
  cm.course_id,
  gm.pk1                   AS gradebook_main_pk1,
  gm.title,
  gm.anonymous_grading_ind AS anonymous_now,
  lifted.lifted_date,
  gm.delegated_grading_ind
FROM gradebook_main gm
JOIN course_main cm ON cm.pk1 = gm.crsmain_pk1
LEFT JOIN (
  SELECT gradebook_main_pk1, max(date_logged) AS lifted_date
  FROM gradebook_log
  WHERE event_key = 'anonymity_lifted'
    -- AND date_logged >= '2026-09-01'   -- optional range; adjust per institution
  GROUP BY gradebook_main_pk1
) lifted ON lifted.gradebook_main_pk1 = gm.pk1
WHERE cm.ultra_status = 'U'
  AND (gm.anonymous_grading_ind = 'Y' OR lifted.gradebook_main_pk1 IS NOT NULL)
ORDER BY cm.course_id, gm.title;
```

### Grades saved with the student's name visible

```sql
-- Submissions on anonymous Ultra columns that were graded while the student's name was revealed.

-- Posted: anonymity already lifted on the column
SELECT
  cm.course_id,
  gm.title,
  u.user_id,
  a.pk1 AS attempt_pk1,
  a.last_graded_date,
  'posted' AS stage
FROM attempt a
JOIN gradebook_grade gg ON gg.pk1 = a.gradebook_grade_pk1
JOIN gradebook_main gm  ON gm.pk1 = gg.gradebook_main_pk1
JOIN course_main cm     ON cm.pk1 = gm.crsmain_pk1
JOIN course_users cu    ON cu.pk1 = gg.course_users_pk1
JOIN users u            ON u.pk1 = cu.users_pk1
WHERE cm.ultra_status = 'U'
  AND a.graded_anonymously_ind = 'N'
  AND a.last_graded_date IS NOT NULL
  AND EXISTS (
    SELECT 1
    FROM gradebook_log gl
    WHERE gl.gradebook_main_pk1 = gm.pk1
      AND gl.event_key = 'anonymity_lifted'
  )

UNION ALL

-- Not yet posted: provisional grade saved while the name was revealed
SELECT
  cm.course_id,
  gm.title,
  u.user_id,
  a.pk1,
  asg.last_graded_date,
  'not yet posted'
FROM attempt_staged_grading asg
JOIN attempt a          ON a.pk1 = asg.attempt_pk1
JOIN gradebook_grade gg ON gg.pk1 = a.gradebook_grade_pk1
JOIN gradebook_main gm  ON gm.pk1 = gg.gradebook_main_pk1
JOIN course_main cm     ON cm.pk1 = gm.crsmain_pk1
JOIN course_users cu    ON cu.pk1 = gg.course_users_pk1
JOIN users u            ON u.pk1 = cu.users_pk1
WHERE cm.ultra_status = 'U'
  AND asg.pending_anonymous_ind = 'Y'
  AND asg.graded_anonymously_ind = 'N'
ORDER BY 1, 2, 3;
```

---

## Not Yet Tested

We have not confirmed the behaviour described above for:

- Group assignments
- Tests and quizzes, including auto-graded and question-level grading
- Anonymous grading combined with delegated grading
- Graders who hold the reveal privilege through a course role rather than as a System Administrator
- Posting only some grades in a column (in our test, posting some grades lifted anonymity for every student in the column)

If you find different behaviour in your environment, please share it through the [Community & Resources](community.md) page so this guidance can be improved.

---

This is a supplemental community resource. Content is the property of Blackboard, Inc. and is provided without official support or endorsement. Always refer to official Blackboard documentation and your institution's agreements.
