/*
Author: Jeff Kelley  Date: 2025-11-17
Anthology retains all rights to this content.
It is provided "AS IS" without support or warranty of any kind, express or implied.
*/

-- Aggregate response counts per deployment
WITH responses AS (
    SELECT
        dr.deployment_pk1,                                  -- Deployment surrogate key
        COUNT(1) AS total_recipients,                       -- Total records in deployment_response
        SUM(CASE WHEN dr.status = 'RE' THEN 1 ELSE 0 END) AS returned_responses -- Count of returned responses
    FROM deployment_response AS dr
    GROUP BY dr.deployment_pk1
)

SELECT
    su.name AS survey_name,                                 -- Survey name
    su.survey_description,                                  -- Survey description
    dp.name AS deployment_name,                             -- Deployment name
    COALESCE(rs.total_recipients, 0) AS total_recipients,   -- Total recipients (0 if no responses row)
    COALESCE(rs.returned_responses, 0) AS returned_responses, -- Returned responses (0 if none)
    CASE
        WHEN COALESCE(rs.total_recipients, 0) = 0
            THEN 0::decimal                                 -- Avoid divide-by-zero
        ELSE ROUND(
            (COALESCE(rs.returned_responses, 0)::decimal
             / rs.total_recipients::decimal) * 100, 2
        )
    END AS response_rate_pct                                -- Response rate as a percentage
FROM deployment AS dp
JOIN clp_sv_survey_deployment AS svdp
    ON svdp.deployment_pk1 = dp.pk1
JOIN clp_sv_survey AS su
    ON su.pk1 = svdp.clp_sv_survey_pk1
LEFT JOIN responses AS rs
    ON rs.deployment_pk1 = dp.pk1
ORDER BY su.name, dp.name;
