-- CTE to aggregate extended data key/value pairs into a single string per gradebook_main_pk1
WITH optionalData AS (
    SELECT 
        gradebook_main_pk1,
        STRING_AGG(extended_data_key || '=' || extended_data_value, ', ') AS extended_data
    FROM bbc_gradecolumn_ext
    GROUP BY gradebook_main_pk1
)

-- Main query to retrieve gradebook details along with formula, schema, and optional extended data
SELECT
    gbm.pk1,                            -- key valude for the grade item
    gbm.title,                         -- Title of the gradebook column
    cm.course_id,                      -- Course identifier
    gbm.possible,                      -- Possible points for the grade item
    gbt.title AS schema,              -- Title of the grading schema
    gbm.visible_ind,                   -- Whether the item is visible
    gbm.visible_in_book_ind,          -- Whether the item is visible in the gradebook
    gbm.date_added,                    -- Date the item was added
    gbm.date_modified,                 -- Date the item was last modified
    gbm.calculated_ind,                -- Whether the item is calculated
    gbm.deleted_ind,                   -- Whether the item is marked as deleted
    gbf.jsonformula,                   -- JSON representation of the formula (if any)
    gbf.version,                       -- Version of the formula
    od.extended_data                   -- Aggregated extended data as key=value pairs
FROM gradebook_main gbm
    LEFT JOIN gradebook_formula gbf 
        ON gbf.gradebook_main_pk1 = gbm.pk1
    JOIN gradebook_translator gbt 
        ON gbt.pk1 = gbm.gradebook_translator_pk1
    JOIN optionalData od 
        ON od.gradebook_main_pk1 = gbm.pk1
    JOIN course_main cm on cm.pk1 = gbm.crsmain_pk1
WHERE gbm.title = 'MM-RESIT1-100%-Essay-ELE112_A-2025/26-MAB001-G01' -- Filter for specific gradebook item