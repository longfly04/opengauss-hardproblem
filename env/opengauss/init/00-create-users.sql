\getenv bench_user BENCH_USER
\getenv bench_password BENCH_PASSWORD
\getenv exporter_user EXPORTER_USER
\getenv exporter_password EXPORTER_PASSWORD

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'bench_user') THEN
    EXECUTE format('CREATE USER %I PASSWORD %L', :'bench_user', :'bench_password');
  END IF;
END
$$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'exporter_user') THEN
    EXECUTE format('CREATE USER %I PASSWORD %L', :'exporter_user', :'exporter_password');
  END IF;
END
$$;
