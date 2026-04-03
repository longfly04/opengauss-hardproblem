-- 使用gs_guc工具设置内存参数
-- 注意：这些命令需要在容器外部执行，这里仅作为参考
-- gs_guc set -N all -I all -c "work_mem=16MB"
-- gs_guc set -N all -I all -c "maintenance_work_mem=512MB"
-- gs_guc set -N all -I all -c "temp_buffers=16MB"

-- 由于在SQL脚本中无法直接执行gs_guc命令，这里仅执行reload
SELECT pg_reload_conf();
