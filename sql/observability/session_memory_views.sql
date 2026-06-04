CREATE SCHEMA IF NOT EXISTS lab_obs;

DO $$
DECLARE
  has_wait_event_type boolean;
  has_wait_event boolean;
  wait_event_type_expr text;
  wait_event_expr text;
BEGIN
  SELECT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'pg_stat_activity'
      AND column_name = 'wait_event_type'
  ) INTO has_wait_event_type;

  SELECT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'pg_stat_activity'
      AND column_name = 'wait_event'
  ) INTO has_wait_event;

  IF has_wait_event_type THEN
    wait_event_type_expr := 'a.wait_event_type';
  ELSE
    wait_event_type_expr := 'NULL::text AS wait_event_type';
  END IF;

  IF has_wait_event THEN
    wait_event_expr := 'a.wait_event';
  ELSE
    wait_event_expr := 'NULL::text AS wait_event';
  END IF;

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

    EXECUTE 'DROP VIEW IF EXISTS lab_obs.session_memory_pressure';
    EXECUTE 'DROP VIEW IF EXISTS lab_obs.session_memory_with_activity';

    EXECUTE format($fmt$
      CREATE OR REPLACE VIEW lab_obs.session_memory_with_activity AS
      SELECT s.datname,
             s.sessid,
             s.total_bytes,
             s.free_bytes,
             s.used_bytes,
             a.pid,
             a.usename,
             a.application_name,
             a.client_addr,
             a.state,
             %s,
             %s,
             a.xact_start,
             a.query_start,
             CASE
               WHEN a.query_start IS NULL THEN NULL
               ELSE extract(epoch FROM clock_timestamp() - a.query_start)::double precision
             END AS query_age_seconds,
             a.query
      FROM lab_obs.session_memory_summary s
      LEFT JOIN pg_stat_activity a
        ON split_part(s.sessid, '.', 2)::bigint = a.sessionid
    $fmt$, wait_event_type_expr, wait_event_expr);

    EXECUTE $sql$
      CREATE OR REPLACE VIEW lab_obs.session_memory_pressure AS
      SELECT datname,
             sessid,
             pid,
             usename,
             application_name,
             client_addr,
             state,
             wait_event_type,
             wait_event,
             xact_start,
             query_start,
             query_age_seconds,
             total_bytes,
             free_bytes,
             used_bytes,
             CASE
               WHEN total_bytes > 0 THEN round((used_bytes::numeric / total_bytes::numeric), 6)
               ELSE NULL
             END AS used_ratio,
             query
      FROM lab_obs.session_memory_with_activity
    $sql$;
  END IF;
END
$$;
