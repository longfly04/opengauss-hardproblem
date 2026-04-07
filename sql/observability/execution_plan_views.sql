CREATE SCHEMA IF NOT EXISTS lab_obs;

DO $$
BEGIN
  EXECUTE $sql$
    CREATE OR REPLACE VIEW lab_obs.execution_plans AS
    SELECT
      coalesce(datname, current_database()) AS datname,
      pid,
      query_start,
      state,
      CASE
        WHEN query LIKE 'EXPLAIN%' THEN 'explain'
        ELSE 'normal'
      END AS query_type,
      query,
      now() - query_start AS duration
    FROM pg_stat_activity
    WHERE query IS NOT NULL
    AND state = 'active'
  $sql$;

  EXECUTE $sql$
    CREATE OR REPLACE VIEW lab_obs.execution_plan_metrics AS
    SELECT
      current_database() AS datname,
      count(*) FILTER (WHERE query_type = 'explain') AS explain_queries_count,
      count(*) FILTER (WHERE query_type = 'normal') AS normal_queries_count,
      avg(EXTRACT(EPOCH FROM duration)) AS avg_query_duration_seconds,
      max(EXTRACT(EPOCH FROM duration)) AS max_query_duration_seconds
    FROM lab_obs.execution_plans
  $sql$;
END
$$;
