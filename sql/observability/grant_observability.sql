\getenv exporter_user EXPORTER_USER

GRANT USAGE ON SCHEMA lab_obs TO :exporter_user;
GRANT SELECT ON ALL TABLES IN SCHEMA lab_obs TO :exporter_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA lab_obs GRANT SELECT ON TABLES TO :exporter_user;
