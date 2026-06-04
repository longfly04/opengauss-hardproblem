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
    CREATE OR REPLACE VIEW lab_obs.selected_settings_raw AS
    SELECT name,
           setting,
           unit,
           source
    FROM pg_settings
    WHERE name IN (
      'shared_buffers',
      'work_mem',
      'maintenance_work_mem',
      'temp_buffers',
      'query_mem',
      'query_max_mem',
      'memorypool_enable',
      'memorypool_size',
      'enable_memory_limit',
      'max_process_memory',
      'cstore_buffers',
      'resilience_memory_reject_percent',
      'max_connections'
    )
  $sql$;

  EXECUTE $sql$
    CREATE OR REPLACE VIEW lab_obs.selected_settings_bytes AS
    SELECT name,
           CASE
             WHEN setting ~ '^-?[0-9]+$' THEN
               CASE unit
                 WHEN '8kB' THEN setting::bigint * 8192
                 WHEN 'kB' THEN setting::bigint * 1024
                 WHEN 'MB' THEN setting::bigint * 1024 * 1024
                 WHEN 'GB' THEN setting::bigint * 1024 * 1024 * 1024
                 ELSE NULL
               END
             ELSE NULL
           END AS setting_bytes,
           setting,
           unit,
           source
    FROM lab_obs.selected_settings_raw
    WHERE name IN (
      'shared_buffers',
      'work_mem',
      'maintenance_work_mem',
      'temp_buffers',
      'query_mem',
      'query_max_mem',
      'memorypool_size',
      'max_process_memory',
      'cstore_buffers'
    )
  $sql$;

  EXECUTE $sql$
    CREATE OR REPLACE VIEW lab_obs.selected_settings_numeric AS
    SELECT name,
           CASE
             WHEN setting ~ '^-?[0-9]+(\.[0-9]+)?$' THEN setting::double precision
             ELSE NULL
           END AS setting_numeric,
           setting,
           unit,
           source
    FROM lab_obs.selected_settings_raw
    WHERE name IN ('max_connections', 'resilience_memory_reject_percent')
  $sql$;

  EXECUTE $sql$
    CREATE OR REPLACE VIEW lab_obs.selected_settings_flags AS
    SELECT name,
           CASE setting
             WHEN 'on' THEN 1
             WHEN 'off' THEN 0
             ELSE NULL
           END::smallint AS setting_flag,
           setting,
           source
    FROM lab_obs.selected_settings_raw
    WHERE name IN ('memorypool_enable', 'enable_memory_limit')
  $sql$;

  EXECUTE $sql$
    CREATE OR REPLACE VIEW lab_obs.selected_settings AS
    SELECT name,
           setting_bytes,
           setting,
           unit,
           source
    FROM lab_obs.selected_settings_bytes
    UNION ALL
    SELECT name,
           setting_numeric::bigint AS setting_bytes,
           setting,
           unit,
           source
    FROM lab_obs.selected_settings_numeric
    WHERE setting_numeric IS NOT NULL
  $sql$;
END
$$;
