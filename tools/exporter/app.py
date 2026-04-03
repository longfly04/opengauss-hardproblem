import os
import time
import logging
import sys
from typing import Iterable, List, Sequence, Tuple

# Configure logging
logging.basicConfig(
    level=logging.DEBUG,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    stream=sys.stdout
)
logger = logging.getLogger(__name__)

import psycopg2
from prometheus_client import REGISTRY, start_http_server
from prometheus_client.core import GaugeMetricFamily

DB_HOST = os.getenv("DB_HOST", "opengauss")
DB_PORT = int(os.getenv("DB_PORT", "5432"))
DB_NAME = os.getenv("DB_NAME", "benchdb")
DB_USER = os.getenv("DB_USER", "exporter")
DB_PASSWORD = os.getenv("DB_PASSWORD", "exporter_123")
EXPORTER_PORT = int(os.getenv("EXPORTER_PORT", "9188"))
SCRAPE_TIMEOUT = int(os.getenv("DB_CONNECT_TIMEOUT", "3"))

QUERIES = {
    "activity": """
        SELECT datname, state, session_count
        FROM lab_obs.activity_sessions
    """,
    "temp_io": """
        SELECT datname, temp_files::bigint, temp_bytes::bigint
        FROM lab_obs.database_spill_stats
    """,
    "session_memory": """
        SELECT datname,
               sessid::text AS sessid,
               total_bytes::bigint,
               free_bytes::bigint,
               used_bytes::bigint
        FROM lab_obs.session_memory_summary
    """,
    "shared_memory": """
        SELECT contextname,
               totalsize::bigint AS total_bytes,
               freesize::bigint AS free_bytes,
               usedsize::bigint AS used_bytes
        FROM lab_obs.shared_memory_contexts
    """,
    "settings": """
        SELECT name, setting_bytes::bigint
        FROM lab_obs.selected_settings
    """,
}


def connect():
    return psycopg2.connect(
        host=DB_HOST,
        port=DB_PORT,
        dbname=DB_NAME,
        user=DB_USER,
        password=DB_PASSWORD,
        connect_timeout=SCRAPE_TIMEOUT,
        application_name="og-memory-exporter",
        sslmode="disable",
    )


def fetch_all(cursor, sql: str) -> List[Tuple]:
    cursor.execute(sql)
    return cursor.fetchall()


class OpenGaussCollector:
    def collect(self) -> Iterable[GaugeMetricFamily]:
        started = time.time()

        collection_success = GaugeMetricFamily(
            "opengauss_exporter_last_collection_success",
            "Whether the last exporter collection succeeded.",
        )
        collection_duration = GaugeMetricFamily(
            "opengauss_exporter_last_collection_duration_seconds",
            "Duration of the last exporter collection in seconds.",
        )
        query_success = GaugeMetricFamily(
            "opengauss_exporter_query_success",
            "Whether a query family collected successfully.",
            labels=["query"],
        )
        activity_sessions = GaugeMetricFamily(
            "opengauss_activity_sessions",
            "Session count by database and state.",
            labels=["database", "state"],
        )
        temp_files = GaugeMetricFamily(
            "opengauss_temp_files_total",
            "Temporary files by database.",
            labels=["database"],
        )
        temp_bytes = GaugeMetricFamily(
            "opengauss_temp_bytes_total",
            "Temporary bytes written by database.",
            labels=["database"],
        )
        session_total = GaugeMetricFamily(
            "opengauss_session_total_bytes",
            "Session memory total bytes aggregated from lab_obs.session_memory_summary.",
            labels=["database", "session"],
        )
        session_free = GaugeMetricFamily(
            "opengauss_session_free_bytes",
            "Session memory free bytes aggregated from lab_obs.session_memory_summary.",
            labels=["database", "session"],
        )
        session_used = GaugeMetricFamily(
            "opengauss_session_used_bytes",
            "Session memory used bytes aggregated from lab_obs.session_memory_summary.",
            labels=["database", "session"],
        )
        shared_total = GaugeMetricFamily(
            "opengauss_shared_context_total_bytes",
            "Shared memory context total bytes.",
            labels=["context"],
        )
        shared_free = GaugeMetricFamily(
            "opengauss_shared_context_free_bytes",
            "Shared memory context free bytes.",
            labels=["context"],
        )
        shared_used = GaugeMetricFamily(
            "opengauss_shared_context_used_bytes",
            "Shared memory context used bytes.",
            labels=["context"],
        )
        setting_bytes = GaugeMetricFamily(
            "opengauss_setting_bytes",
            "Selected byte-sized database settings.",
            labels=["setting"],
        )

        families: Sequence[GaugeMetricFamily] = [
            collection_success,
            collection_duration,
            query_success,
            activity_sessions,
            temp_files,
            temp_bytes,
            session_total,
            session_free,
            session_used,
            shared_total,
            shared_free,
            shared_used,
            setting_bytes,
        ]

        overall_success = True

        try:
            logger.debug(f"Attempting to connect to {DB_HOST}:{DB_PORT}/{DB_NAME} as {DB_USER}")
            with connect() as conn:
                logger.debug("Connection successful")
                conn.autocommit = True
                with conn.cursor() as cursor:
                    for query_name, metric_handler in (
                        ("activity", lambda rows: [activity_sessions.add_metric([str(dat), str(state)], float(count)) for dat, state, count in rows]),
                        ("temp_io", lambda rows: [(
                            temp_files.add_metric([str(dat)], float(files)),
                            temp_bytes.add_metric([str(dat)], float(bytes_written))
                        ) for dat, files, bytes_written in rows]),
                        ("session_memory", lambda rows: [(
                            session_total.add_metric([str(dat), str(sess)], float(total)),
                            session_free.add_metric([str(dat), str(sess)], float(free)),
                            session_used.add_metric([str(dat), str(sess)], float(used))
                        ) for dat, sess, total, free, used in rows]),
                        ("shared_memory", lambda rows: [(
                            shared_total.add_metric([str(context)], float(total)),
                            shared_free.add_metric([str(context)], float(free)),
                            shared_used.add_metric([str(context)], float(used))
                        ) for context, total, free, used in rows]),
                        ("settings", lambda rows: [setting_bytes.add_metric([str(name)], float(value)) for name, value in rows]),
                    ):
                        try:
                            logger.debug(f"Executing query: {query_name}")
                            rows = fetch_all(cursor, QUERIES[query_name])
                            logger.debug(f"Query returned {len(rows)} rows")
                            metric_handler(rows)
                            query_success.add_metric([query_name], 1)
                            logger.debug(f"Query {query_name} succeeded")
                        except Exception as e:
                            logger.error(f"Query {query_name} failed: {e}")
                            overall_success = False
                            query_success.add_metric([query_name], 0)
        except Exception as e:
            logger.error(f"Connection failed: {e}")
            overall_success = False
            for query_name in QUERIES:
                query_success.add_metric([query_name], 0)

        collection_success.add_metric([], 1 if overall_success else 0)
        collection_duration.add_metric([], time.time() - started)

        return families


if __name__ == "__main__":
    REGISTRY.register(OpenGaussCollector())
    start_http_server(EXPORTER_PORT)
    while True:
        time.sleep(60)
