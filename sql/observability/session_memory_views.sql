CREATE SCHEMA IF NOT EXISTS lab_obs;

DO $$
BEGIN
  EXECUTE $sql$
    CREATE OR REPLACE VIEW lab_obs.activity_sessions AS
    SELECT coalesce(datname, current_database()) AS datname,
           coalesce(state, 'unknown') AS state,
           count(*)::bigint AS session_count
    FROM pg_stat_activity
    GROUP BY coalesce(datname, current_database()), coalesce(state, 'unknown')
  $sql$;

  IF EXISTS (
    SELECT 1
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE c.relname = 'gs_session_memory_detail'
  ) THEN
    EXECUTE $sql$
      CREATE OR REPLACE VIEW lab_obs.session_memory_summary AS
      SELECT current_database() AS datname,
             sessid,
             sum(totalsize)::bigint AS total_bytes,
             sum(freesize)::bigint AS free_bytes,
             sum(usedsize)::bigint AS used_bytes
      FROM gs_session_memory_detail
      GROUP BY sessid
    $sql$;

    EXECUTE $sql$
      CREATE OR REPLACE VIEW lab_obs.session_memory_with_activity AS
      SELECT s.datname,
             s.sessid,
             s.total_bytes,
             s.free_bytes,
             s.used_bytes,
             a.pid,
             a.state,
             a.query_start,
             a.query
      FROM lab_obs.session_memory_summary s
      LEFT JOIN pg_stat_activity a
        ON a.sessionid = s.sessid
    $sql$;
  END IF;
END
$$;
