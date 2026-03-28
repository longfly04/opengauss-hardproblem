ALTER SYSTEM SET track_activities = on;
ALTER SYSTEM SET track_counts = on;
ALTER SYSTEM SET log_temp_files = 0;
ALTER SYSTEM SET log_min_duration_statement = 0;
ALTER SYSTEM SET work_mem = '8MB';
ALTER SYSTEM SET maintenance_work_mem = '256MB';
ALTER SYSTEM SET temp_buffers = '8MB';
SELECT pg_reload_conf();
