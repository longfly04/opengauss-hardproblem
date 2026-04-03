DO $$
DECLARE
  bench_user text := 'bench';
  bench_password text := 'bench_123';
  exporter_user text := 'exporter';
  exporter_password text := 'exporter_123';
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = bench_user) THEN
    EXECUTE format('CREATE USER %I PASSWORD %L', bench_user, bench_password);
  END IF;
  
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = exporter_user) THEN
    EXECUTE format('CREATE USER %I PASSWORD %L', exporter_user, exporter_password);
  END IF;
END
$$;
