ALTER SYSTEM SET track_activities = on;
ALTER SYSTEM SET track_counts = on;
ALTER SYSTEM SET log_temp_files = 0;
ALTER SYSTEM SET log_min_duration_statement = 1000;
ALTER SYSTEM SET work_mem = '64MB';
ALTER SYSTEM SET maintenance_work_mem = '1GB';
ALTER SYSTEM SET temp_buffers = '32MB';
SELECT pg_reload_conf();
