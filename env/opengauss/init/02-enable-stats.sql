\getenv db_name DB_NAME
\getenv bench_user BENCH_USER
\getenv exporter_user EXPORTER_USER

ALTER SYSTEM SET track_activities = on;
ALTER SYSTEM SET track_counts = on;
ALTER SYSTEM SET log_temp_files = 0;
ALTER SYSTEM SET log_min_duration_statement = 1000;
SELECT pg_reload_conf();

DO $$
BEGIN
  EXECUTE format('GRANT CONNECT ON DATABASE %I TO %I', :'db_name', :'bench_user');
  EXECUTE format('GRANT CONNECT ON DATABASE %I TO %I', :'db_name', :'exporter_user');
END
$$;
