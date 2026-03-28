CREATE SCHEMA IF NOT EXISTS lab_obs;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE c.relname = 'gs_shared_memory_detail'
  ) THEN
    EXECUTE $sql$
      CREATE OR REPLACE VIEW lab_obs.shared_memory_contexts AS
      SELECT current_database() AS database_name,
             contextname,
             level,
             parent,
             totalsize,
             freesize,
             usedsize
      FROM gs_shared_memory_detail
    $sql$;

    EXECUTE $sql$
      CREATE OR REPLACE VIEW lab_obs.shared_memory_totals AS
      SELECT current_database() AS database_name,
             sum(totalsize)::bigint AS total_bytes,
             sum(freesize)::bigint AS free_bytes,
             sum(usedsize)::bigint AS used_bytes
      FROM gs_shared_memory_detail
    $sql$;
  END IF;
END
$$;

DO $$
BEGIN
  EXECUTE $sql$
    CREATE OR REPLACE VIEW lab_obs.selected_settings AS
    SELECT name,
           CASE unit
             WHEN '8kB' THEN setting::bigint * 8192
             WHEN 'kB' THEN setting::bigint * 1024
             WHEN 'MB' THEN setting::bigint * 1024 * 1024
             WHEN 'GB' THEN setting::bigint * 1024 * 1024 * 1024
             ELSE setting::bigint
           END AS setting_bytes,
           setting,
           unit,
           source
    FROM pg_settings
    WHERE name IN ('shared_buffers', 'work_mem', 'maintenance_work_mem', 'temp_buffers', 'max_connections')
  $sql$;
END
$$;
