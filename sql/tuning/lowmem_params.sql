ALTER SYSTEM SET track_activities = on;
ALTER SYSTEM SET track_counts = on;
ALTER SYSTEM SET log_temp_files = 0;
ALTER SYSTEM SET log_min_duration_statement = 500;
ALTER SYSTEM SET work_mem = '16MB';
ALTER SYSTEM SET maintenance_work_mem = '512MB';
ALTER SYSTEM SET temp_buffers = '16MB';
SELECT pg_reload_conf();
