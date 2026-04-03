-- track_activities 和 track_counts 已经默认开启，不需要通过 ALTER SYSTEM 设置
-- log_temp_files 和 log_min_duration_statement 需要在配置文件中设置，不支持 ALTER SYSTEM
SELECT pg_reload_conf();

DO $$
DECLARE
  db_name text := 'benchdb';
  bench_user text := 'bench';
  exporter_user text := 'exporter';
BEGIN
  EXECUTE format('GRANT CONNECT ON DATABASE %I TO %I', db_name, bench_user);
  EXECUTE format('GRANT CONNECT ON DATABASE %I TO %I', db_name, exporter_user);
END
$$;
