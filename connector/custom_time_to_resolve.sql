-- This query is intended to be run as a custom query in a BigQuery datasource for the datastudio dashboard
-- Calculate MTTR using start and end time of the incident where a deploy ID is not available
WITH
  last_three_months AS (
    SELECT
      TIMESTAMP(day) AS day
    FROM
      UNNEST(
        GENERATE_DATE_ARRAY(
          DATE_SUB(CURRENT_DATE(), INTERVAL 3 MONTH),
          CURRENT_DATE(),
          INTERVAL 1 DAY)) AS day
    # FROM the start of the data
    WHERE day > (SELECT date(min(time_created)) FROM four_keys.events_raw)
  )
SELECT
  FORMAT_TIMESTAMP('%Y%m%d', day) AS day,
  # Daily metrics
  median_time_to_resolve_custom,
  CASE
    WHEN max(med_time_to_resolve_bucket_custom) OVER () < 24 THEN "One day"
    WHEN max(med_time_to_resolve_bucket_custom) OVER () < 168 THEN "One week"
    WHEN max(med_time_to_resolve_bucket_custom) OVER () < 672 THEN "One month"
    WHEN max(med_time_to_resolve_bucket_custom) OVER () < 730 * 6 THEN "Six months"
    ELSE "One year"
    END AS time_to_restore_buckets_custom
FROM
  (
    SELECT
      e.day,
      CASE WHEN IFNULL(ANY_VALUE(med_time_to_resolve_with_deploy), 0) > 0 THEN IFNULL(ANY_VALUE(med_time_to_resolve_with_deploy), 0)
           ELSE IFNULL(ANY_VALUE(med_time_to_resolve_without_deploy), 0)
           END AS median_time_to_resolve_custom,
      CASE WHEN ANY_VALUE(med_time_to_resolve_with_deploy_bucket) > 0 THEN ANY_VALUE(med_time_to_resolve_with_deploy_bucket)
           ELSE ANY_VALUE(med_time_to_resolve_without_deploy_bucket)
           END AS med_time_to_resolve_bucket_custom
    FROM last_three_months e
    LEFT JOIN
      (
        SELECT
          d.deploy_id,
          TIMESTAMP_TRUNC(d.time_created, DAY) AS day,
          #### Median time to resolve
          PERCENTILE_CONT(
            TIMESTAMP_DIFF(time_resolved, d.time_created, HOUR), 0.5)
            OVER (
              PARTITION BY TIMESTAMP_TRUNC(d.time_created, DAY)
            ) AS med_time_to_resolve_with_deploy,
          PERCENTILE_CONT(
            TIMESTAMP_DIFF(time_resolved, d.time_created, HOUR), 0.5)
            OVER () AS med_time_to_resolve_with_deploy_bucket,
        FROM four_keys.deployments d, d.changes
        LEFT JOIN four_keys.changes c
          ON changes = c.change_id
        LEFT JOIN
          (
            SELECT
              incident_id,
              change,
              time_resolved,
              time_created
            FROM
              four_keys.incidents i,
              i.changes change
          ) i
          ON i.change = changes
      ) d
      ON d.day = e.day
    LEFT JOIN
      (
        SELECT
          TIMESTAMP_TRUNC(i.time_created, DAY) AS day,
          PERCENTILE_CONT(
            TIMESTAMP_DIFF(time_resolved, i.time_created, HOUR), 0.5)
            OVER (
              PARTITION BY TIMESTAMP_TRUNC(i.time_created, DAY)
            ) AS med_time_to_resolve_without_deploy,
          PERCENTILE_CONT(
            TIMESTAMP_DIFF(time_resolved, i.time_created, HOUR), 0.5)
            OVER () AS med_time_to_resolve_without_deploy_bucket
         FROM four_keys.incidents i
      ) i
      ON i.day = e.day
    GROUP BY day
  )
