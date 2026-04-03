CREATE SCHEMA IF NOT EXISTS lab_obs;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE c.relname = 'pg_stat_database'
  ) THEN
    EXECUTE $sql$
      CREATE OR REPLACE VIEW lab_obs.database_spill_stats AS
      SELECT datname,
             temp_files,
             temp_bytes,
             blks_read,
             blks_hit,
             tup_returned,
             tup_fetched,
             tup_inserted,
             tup_updated,
             tup_deleted
      FROM pg_stat_database
    $sql$;
  END IF;
END
$$;
