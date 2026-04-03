-- track_activities 和 track_counts 已经默认开启，不支持 ALTER SYSTEM 设置
-- log_temp_files 和 log_min_duration_statement 需要在配置文件中设置，不支持 ALTER SYSTEM
-- work_mem, maintenance_work_mem, temp_buffers 也需要在配置文件中设置，不支持 ALTER SYSTEM
SELECT pg_reload_conf();
