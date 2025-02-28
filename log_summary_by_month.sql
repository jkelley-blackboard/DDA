-- Provided without warranty or support
-- jeff.kelley@anthology.com
-- sumarizes a count of log files and their total size by month

SELECT
    CONCAT(
        SPLIT_PART(url.full_path, '/', 4), '/',
        SPLIT_PART(url.full_path, '/', 5), '/'
    ) AS month,
    COUNT(file.file_id) AS file_count,
    pg_size_pretty(SUM(file.file_size)) AS total_size
FROM
    xyf_files file
JOIN
    xyf_urls url ON file.file_id = url.file_id
WHERE
    url.full_path LIKE '%/internal/logs/%'
    AND file.file_type_code = 'F'
GROUP BY
    month
ORDER BY
    month ASC;
