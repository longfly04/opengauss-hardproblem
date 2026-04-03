-- 以下参数在 openGauss 中不支持 ALTER SYSTEM 设置，需要在 postgresql.conf 中配置
-- ALTER SYSTEM SET track_activities = on;
-- ALTER SYSTEM SET track_counts = on;
-- ALTER SYSTEM SET log_temp_files = 0;
-- ALTER SYSTEM SET log_min_duration_statement = 0;
-- ALTER SYSTEM SET work_mem = '8MB';
-- ALTER SYSTEM SET maintenance_work_mem = '256MB';
-- ALTER SYSTEM SET temp_buffers = '8MB';

-- 只执行可以动态重载的配置
SELECT pg_reload_conf();
