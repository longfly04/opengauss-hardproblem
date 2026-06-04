import csv
import json
import logging
import os
import re
import sys
import time
from collections import defaultdict
from datetime import datetime
from pathlib import Path
from typing import Dict, Iterable, List, Sequence, Tuple

import psycopg2
from prometheus_client import REGISTRY, start_http_server
from prometheus_client.core import GaugeMetricFamily

logging.basicConfig(
    level=logging.DEBUG,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    stream=sys.stdout,
)
logger = logging.getLogger(__name__)

DB_HOST = os.getenv("DB_HOST", "opengauss")
DB_PORT = int(os.getenv("DB_PORT", "5432"))
DB_NAME = os.getenv("DB_NAME", "benchdb")
DB_USER = os.getenv("DB_USER", "exporter")
DB_PASSWORD = os.getenv("DB_PASSWORD", "exporter_123")
EXPORTER_PORT = int(os.getenv("EXPORTER_PORT", "9188"))
SCRAPE_TIMEOUT = int(os.getenv("DB_CONNECT_TIMEOUT", "3"))
RUNS_DIR = Path(os.getenv("RUNS_DIR", "/workspace/experiments/runs"))
RUN_DIR_PATTERN = re.compile(r"^\d{8}-\d{6}-")
SYSBENCH_EXPORT_GRACE_SECONDS = int(os.getenv("SYSBENCH_EXPORT_GRACE_SECONDS", str(30 * 60)))

SYSBENCH_LOG_PATTERN = re.compile(
    r"\[\s*(\d+)s\s*\]\s*thds:\s*(\d+)\s*tps:\s*([\d.]+)\s*qps:\s*([\d.]+)\s*"
    r"\(r/w/o:\s*([\d.]+)/([\d.]+)/([\d.]+)\)\s*lat\s*\(ms,95%\):\s*([\d.]+)\s*"
    r"err/s:\s*([\d.]+)\s*reconn/s:\s*([\d.]+)"
)
PLAN_DURATION_SANITY_MAX_MS = float(os.getenv("PLAN_DURATION_SANITY_MAX_MS", str(24 * 60 * 60 * 1000)))

QUERIES = {
    "activity": """
        SELECT datname, state, session_count
        FROM lab_obs.activity_sessions
    """,
    "temp_io": """
        SELECT datname, temp_files::bigint, temp_bytes::bigint
        FROM lab_obs.database_spill_stats
    """,
    "session_memory_pressure": """
        SELECT datname,
               coalesce(sessid::text, '') AS sessid,
               coalesce(pid::text, '0') AS pid,
               coalesce(usename, '') AS usename,
               coalesce(application_name, '') AS application_name,
               coalesce(state, 'unknown') AS state,
               coalesce(wait_event_type, '') AS wait_event_type,
               coalesce(total_bytes, 0)::double precision AS total_bytes,
               coalesce(free_bytes, 0)::double precision AS free_bytes,
               coalesce(used_bytes, 0)::double precision AS used_bytes,
               coalesce(used_ratio, 0)::double precision AS used_ratio,
               coalesce(query_age_seconds, 0)::double precision AS query_age_seconds
        FROM lab_obs.session_memory_pressure
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
    "setting_flags": """
        SELECT name, setting_flag::smallint
        FROM lab_obs.selected_settings_flags
    """,
    "execution_plans": """
        SELECT datname, query_type, count(*) AS query_count
        FROM lab_obs.execution_plans
        GROUP BY datname, query_type
    """,
    "execution_plan_metrics": """
        SELECT datname,
               explain_queries_count,
               normal_queries_count,
               avg_query_duration_seconds,
               max_query_duration_seconds
        FROM lab_obs.execution_plan_metrics
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


def fetch_all(cursor, sql: str):
    cursor.execute(sql)
    return cursor.fetchall()


def safe_float(value) -> float:
    if value is None or value == "":
        return 0.0
    if isinstance(value, bool):
        return float(int(value))
    try:
        return float(value)
    except (TypeError, ValueError):
        return 0.0


def read_json_file(path: Path) -> Dict:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def read_tsv_rows(path: Path) -> List[Dict[str, str]]:
    with path.open("r", encoding="utf-8", newline="") as handle:
        return list(csv.DictReader(handle, delimiter="\t"))


def read_run_summary(path: Path) -> Dict[str, str]:
    if not path.exists():
        return {}

    summary: Dict[str, str] = {}
    with path.open("r", encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if not line or "=" not in line:
                continue
            key, value = line.split("=", 1)
            summary[key] = value
    return summary


def iter_run_dirs() -> List[Path]:
    if not RUNS_DIR.exists():
        return []
    return sorted(
        path
        for path in RUNS_DIR.iterdir()
        if path.is_dir() and RUN_DIR_PATTERN.match(path.name)
    )


def iter_plan_analysis_dirs() -> List[Path]:
    analysis_dirs: List[Path] = []
    for run_dir in iter_run_dirs():
        plan_root = run_dir / "plan-analysis"
        if not plan_root.is_dir():
            continue
        for analysis_dir in sorted(path for path in plan_root.iterdir() if path.is_dir()):
            analysis_dirs.append(analysis_dir)
    return analysis_dirs


def iter_tpch_run_dirs() -> List[Path]:
    tpch_dirs: List[Path] = []
    for run_dir in iter_run_dirs():
        tpch_dir = run_dir / "tp" / "tpch"
        if tpch_dir.is_dir():
            tpch_dirs.append(tpch_dir)
    return tpch_dirs


def iter_validation_summary_files() -> List[Path]:
    return [run_dir / "validation-summary.tsv" for run_dir in iter_run_dirs() if (run_dir / "validation-summary.tsv").is_file()]


def iter_sysbench_logs() -> List[Path]:
    logs: List[Path] = []
    for run_dir in iter_run_dirs():
        log_path = run_dir / "tp" / "sysbench-run.log"
        if log_path.is_file():
            logs.append(log_path)
    return logs


def get_run_labels(run_dir: Path) -> Tuple[str, str, str]:
    run_summary = read_run_summary(run_dir / "run-summary.env")
    run_id = str(run_summary.get("run_id") or run_dir.name)
    scenario_name = str(run_summary.get("scenario_name") or "")
    runner = str(run_summary.get("tp_runner") or "").strip()
    if not runner:
        if (run_dir / "tp" / "sysbench-run.log").is_file():
            runner = "sysbench"
        elif (run_dir / "tp" / "tpcc-run.log").is_file():
            runner = "tpcc"
        elif (run_dir / "tp" / "tpch").is_dir():
            runner = "tpch"
    return run_id, scenario_name, runner


def get_run_start_epoch(run_dir: Path) -> float:
    run_summary = read_run_summary(run_dir / "run-summary.env")
    started_at = str(run_summary.get("started_at") or "").strip()
    if started_at:
        try:
            return datetime.fromisoformat(started_at.replace("Z", "+00:00")).timestamp()
        except ValueError:
            pass

    match = RUN_DIR_PATTERN.match(run_dir.name)
    if not match:
        return 0.0

    try:
        return datetime.strptime(match.group(0), "%Y%m%d-%H%M%S-").timestamp()
    except ValueError:
        return 0.0


def get_run_finish_epoch(run_dir: Path) -> float:
    run_summary = read_run_summary(run_dir / "run-summary.env")
    finished_at = str(run_summary.get("finished_at") or "").strip()
    if finished_at:
        try:
            return datetime.fromisoformat(finished_at.replace("Z", "+00:00")).timestamp()
        except ValueError:
            pass
    return 0.0


def is_reasonable_duration_ms(value: float) -> bool:
    return value > 0 and value <= PLAN_DURATION_SANITY_MAX_MS


def normalize_plan_query_summary_row(row: Dict[str, str]) -> Dict[str, object]:
    query_name = str(row.get("query_name") or "").strip()
    execution_time_ms = safe_float(row.get("plan_execution_time_ms"))
    max_exclusive_duration_ms = safe_float(row.get("max_exclusive_duration_ms"))
    invalid_operator_count = safe_float(row.get("invalid_operator_count"))
    parse_status = str(row.get("parse_status") or "ok").strip().lower()
    duration_status = str(row.get("duration_sanity_status") or "").strip().lower()
    has_duration_status = "duration_sanity_status" in row
    duration_ok = duration_status in {"", "ok"} if has_duration_status else True

    if not has_duration_status:
        if not is_reasonable_duration_ms(execution_time_ms):
            duration_ok = False
            if is_reasonable_duration_ms(max_exclusive_duration_ms):
                execution_time_ms = max_exclusive_duration_ms
        elif (
            is_reasonable_duration_ms(max_exclusive_duration_ms)
            and execution_time_ms < max_exclusive_duration_ms
        ):
            duration_ok = False
            execution_time_ms = max_exclusive_duration_ms

    if not is_reasonable_duration_ms(max_exclusive_duration_ms):
        max_exclusive_duration_ms = 0.0
    if not is_reasonable_duration_ms(execution_time_ms):
        execution_time_ms = 0.0
    if execution_time_ms <= 0 and max_exclusive_duration_ms > 0:
        execution_time_ms = max_exclusive_duration_ms
    if not duration_ok:
        invalid_operator_count = max(invalid_operator_count, 1.0)

    return {
        "query_name": query_name,
        "execution_time_ms": execution_time_ms,
        "max_exclusive_duration_ms": max_exclusive_duration_ms,
        "max_exclusive_cost": safe_float(row.get("max_exclusive_cost")),
        "temp_written_blocks": safe_float(row.get("sum_temp_written_blocks")),
        "external_sort_nodes": safe_float(row.get("external_sort_node_count")),
        "parse_ok": 1.0 if parse_status == "ok" else 0.0,
        "duration_ok": 1.0 if duration_ok else 0.0,
        "invalid_operator_count": invalid_operator_count,
    }


def load_plan_query_summary(path: Path) -> Dict[str, Dict[str, object]]:
    rows: Dict[str, Dict[str, object]] = {}
    if not path.is_file():
        return rows

    for row in read_tsv_rows(path):
        normalized = normalize_plan_query_summary_row(row)
        query_name = str(normalized.get("query_name") or "")
        if query_name:
            rows[query_name] = normalized
    return rows


def summarize_tpch_rows(rows: List[Dict[str, object]]) -> Tuple[int, float, float, float]:
    query_count = sum(1 for row in rows if safe_float(row.get("completed")) > 0)
    durations = [safe_float(row.get("duration_seconds")) for row in rows if safe_float(row.get("duration_seconds")) > 0]
    if not durations:
        return query_count, 0.0, 0.0, 0.0
    return query_count, sum(durations), sum(durations) / len(durations), max(durations)


def build_tpch_query_rows(run_dir: Path) -> List[Dict[str, object]]:
    tpch_dir = run_dir / "tp" / "tpch"
    if not tpch_dir.is_dir():
        return []

    rows_by_query: Dict[str, Dict[str, object]] = {}
    summary_path = tpch_dir / "summary.tsv"
    if summary_path.is_file():
        for row in read_tsv_rows(summary_path):
            query_name = str(row.get("query_name") or "").strip().removesuffix(".sql")
            if not query_name:
                continue
            plan_file = str(row.get("plan_file") or "")
            rows_by_query[query_name] = {
                "query_name": query_name,
                "duration_seconds": safe_float(row.get("duration_seconds")),
                "has_plan": 1.0 if plan_file else 0.0,
                "completed": 1.0,
            }

    plan_rows = load_plan_query_summary(run_dir / "plan-analysis" / "tpch" / "query-summary.tsv")
    for query_name, plan_row in plan_rows.items():
        entry = rows_by_query.setdefault(
            query_name,
            {"query_name": query_name, "duration_seconds": 0.0, "has_plan": 0.0, "completed": 0.0},
        )
        if safe_float(entry.get("duration_seconds")) <= 0:
            entry["duration_seconds"] = safe_float(plan_row.get("execution_time_ms")) / 1000.0
        entry["completed"] = 1.0

    for plan_path in sorted(tpch_dir.glob("*.plan")):
        query_name = plan_path.stem
        entry = rows_by_query.setdefault(
            query_name,
            {"query_name": query_name, "duration_seconds": 0.0, "has_plan": 0.0, "completed": 0.0},
        )
        entry["has_plan"] = 1.0

    for log_path in sorted(tpch_dir.glob("*.log")):
        query_name = log_path.stem
        entry = rows_by_query.setdefault(
            query_name,
            {"query_name": query_name, "duration_seconds": 0.0, "has_plan": 0.0, "completed": 0.0},
        )
        entry["completed"] = 1.0

    return [rows_by_query[query_name] for query_name in sorted(rows_by_query)]


def parse_validation_summary(path: Path) -> Dict[str, float]:
    metrics: Dict[str, float] = {}
    if not path.is_file():
        return metrics
    for row in read_tsv_rows(path):
        metric = str(row.get("metric") or "").strip()
        if not metric:
            continue
        metrics[metric] = safe_float(row.get("value"))
    return metrics


def parse_sysbench_log(path: Path) -> List[Dict[str, float]]:
    samples: List[Dict[str, float]] = []
    if not path.is_file():
        return samples

    with path.open("r", encoding="utf-8", errors="ignore") as handle:
        for line in handle:
            match = SYSBENCH_LOG_PATTERN.search(line.strip())
            if not match:
                continue
            samples.append(
                {
                    "second": float(match.group(1)),
                    "threads": float(match.group(2)),
                    "tps": float(match.group(3)),
                    "qps": float(match.group(4)),
                    "read_qps": float(match.group(5)),
                    "write_qps": float(match.group(6)),
                    "other_qps": float(match.group(7)),
                    "latency_p95_ms": float(match.group(8)),
                    "errors_per_sec": float(match.group(9)),
                    "reconnections_per_sec": float(match.group(10)),
                }
            )
    return samples


def parse_tpch_query_rows(summary_path: Path) -> List[Dict[str, object]]:
    rows: List[Dict[str, object]] = []
    if not summary_path.is_file():
        return rows

    for row in read_tsv_rows(summary_path):
        query_name = str(row.get("query_name") or "").strip()
        if not query_name:
            continue
        plan_file = str(row.get("plan_file") or "")
        rows.append(
            {
                "query_name": query_name.removesuffix(".sql"),
                "duration_seconds": safe_float(row.get("duration_seconds")),
                "has_plan": 1.0 if plan_file else 0.0,
            }
        )
    return rows


def parse_injection_artifacts(run_dir: Path) -> Dict[str, object]:
    injection_dir = run_dir / "injection"
    if not injection_dir.is_dir():
        return {"start_epoch": 0.0, "round_count": 0.0, "queries": []}

    start_epoch = 0.0
    start_path = injection_dir / "injection_start_epoch.txt"
    if start_path.is_file():
        try:
            start_epoch = safe_float(start_path.read_text(encoding="utf-8").strip())
        except OSError:
            start_epoch = 0.0

    queries: List[Dict[str, object]] = []
    round_dirs = sorted(path for path in injection_dir.glob("round-*") if path.is_dir())
    for round_dir in round_dirs:
        round_name = round_dir.name
        analysis_summary_path = run_dir / "plan-analysis" / round_name / "query-summary.tsv"
        analysis_rows = load_plan_query_summary(analysis_summary_path)
        for plan_path in sorted(round_dir.glob("*.plan")):
            query_name = plan_path.stem
            analysis_row = analysis_rows.get(query_name, {})
            queries.append(
                {
                    "round": round_name,
                    "query_name": query_name,
                    "execution_time_ms": safe_float(analysis_row.get("execution_time_ms")),
                    "temp_written_blocks": safe_float(analysis_row.get("temp_written_blocks")),
                    "external_sort_nodes": safe_float(analysis_row.get("external_sort_nodes")),
                }
            )

    return {
        "start_epoch": start_epoch,
        "round_count": float(len(round_dirs)),
        "queries": queries,
    }


def get_plan_labels(analysis_dir: Path, summary: Dict) -> Tuple[str, str, str]:
    run_dir = analysis_dir.parent.parent
    run_id, scenario_name, _runner = get_run_labels(run_dir)
    resolved_run_id = str(summary.get("run_id") or run_id)
    resolved_scenario_name = str(summary.get("scenario_name") or scenario_name)
    analysis_name = str(summary.get("analysis_name") or analysis_dir.name)
    return resolved_run_id, resolved_scenario_name, analysis_name


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
            "Session memory total bytes from lab_obs.session_memory_pressure.",
            labels=["database", "session", "pid", "state", "user", "application", "wait_event_type"],
        )
        session_free = GaugeMetricFamily(
            "opengauss_session_free_bytes",
            "Session memory free bytes from lab_obs.session_memory_pressure.",
            labels=["database", "session", "pid", "state", "user", "application", "wait_event_type"],
        )
        session_used = GaugeMetricFamily(
            "opengauss_session_used_bytes",
            "Session memory used bytes from lab_obs.session_memory_pressure.",
            labels=["database", "session", "pid", "state", "user", "application", "wait_event_type"],
        )
        session_pressure_ratio = GaugeMetricFamily(
            "opengauss_session_memory_used_ratio",
            "Session memory used ratio from lab_obs.session_memory_pressure.",
            labels=["database", "session", "pid", "state", "user", "application", "wait_event_type"],
        )
        session_query_elapsed = GaugeMetricFamily(
            "opengauss_session_query_elapsed_seconds",
            "Session query elapsed seconds from lab_obs.session_memory_pressure.",
            labels=["database", "session", "pid", "state", "user", "application", "wait_event_type"],
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
            "Selected numeric database settings normalized to bytes or numeric values.",
            labels=["setting"],
        )
        setting_flag = GaugeMetricFamily(
            "opengauss_setting_flag",
            "Selected boolean-like database settings exposed as 0/1 flags.",
            labels=["setting"],
        )
        execution_plan_queries = GaugeMetricFamily(
            "opengauss_execution_plan_queries",
            "Execution plan query count by database and query type.",
            labels=["database", "query_type"],
        )
        execution_plan_explain_count = GaugeMetricFamily(
            "opengauss_execution_plan_explain_count",
            "Count of EXPLAIN queries by database.",
            labels=["database"],
        )
        execution_plan_normal_count = GaugeMetricFamily(
            "opengauss_execution_plan_normal_count",
            "Count of normal queries by database.",
            labels=["database"],
        )
        execution_plan_avg_duration = GaugeMetricFamily(
            "opengauss_execution_plan_avg_duration_seconds",
            "Average query duration by database.",
            labels=["database"],
        )
        execution_plan_max_duration = GaugeMetricFamily(
            "opengauss_execution_plan_max_duration_seconds",
            "Maximum query duration by database.",
            labels=["database"],
        )

        validation_metric = GaugeMetricFamily(
            "opengauss_run_validation_metric",
            "Validation summary metric from run artifacts.",
            labels=["run", "scenario", "runner", "metric"],
        )
        sysbench_threads = GaugeMetricFamily(
            "opengauss_run_sysbench_threads",
            "Observed sysbench thread count from run log samples.",
            labels=["run", "scenario", "runner", "threads"],
        )
        sysbench_tps = GaugeMetricFamily(
            "opengauss_run_sysbench_tps",
            "Sysbench TPS from run log samples.",
            labels=["run", "scenario", "runner", "threads"],
        )
        sysbench_qps = GaugeMetricFamily(
            "opengauss_run_sysbench_qps",
            "Sysbench QPS from run log samples.",
            labels=["run", "scenario", "runner", "threads"],
        )
        sysbench_read_qps = GaugeMetricFamily(
            "opengauss_run_sysbench_read_qps",
            "Sysbench read QPS from run log samples.",
            labels=["run", "scenario", "runner", "threads"],
        )
        sysbench_write_qps = GaugeMetricFamily(
            "opengauss_run_sysbench_write_qps",
            "Sysbench write QPS from run log samples.",
            labels=["run", "scenario", "runner", "threads"],
        )
        sysbench_other_qps = GaugeMetricFamily(
            "opengauss_run_sysbench_other_qps",
            "Sysbench other QPS from run log samples.",
            labels=["run", "scenario", "runner", "threads"],
        )
        sysbench_latency_p95 = GaugeMetricFamily(
            "opengauss_run_sysbench_latency_p95_ms",
            "Sysbench p95 latency from run log samples.",
            labels=["run", "scenario", "runner", "threads"],
        )
        sysbench_errors = GaugeMetricFamily(
            "opengauss_run_sysbench_errors_per_sec",
            "Sysbench errors per second from run log samples.",
            labels=["run", "scenario", "runner", "threads"],
        )
        sysbench_reconnections = GaugeMetricFamily(
            "opengauss_run_sysbench_reconnections_per_sec",
            "Sysbench reconnections per second from run log samples.",
            labels=["run", "scenario", "runner", "threads"],
        )

        tpch_run_query_count = GaugeMetricFamily(
            "opengauss_tpch_run_query_count",
            "Completed TPCH query count from run-scoped summary artifacts.",
            labels=["run", "scenario"],
        )
        tpch_run_total_duration = GaugeMetricFamily(
            "opengauss_tpch_run_total_duration_seconds",
            "Summed TPCH query duration from run-scoped summary artifacts.",
            labels=["run", "scenario"],
        )
        tpch_run_avg_duration = GaugeMetricFamily(
            "opengauss_tpch_run_avg_query_duration_seconds",
            "Average TPCH query duration from run-scoped summary artifacts.",
            labels=["run", "scenario"],
        )
        tpch_run_max_duration = GaugeMetricFamily(
            "opengauss_tpch_run_max_query_duration_seconds",
            "Maximum TPCH query duration from run-scoped summary artifacts.",
            labels=["run", "scenario"],
        )
        tpch_query_duration = GaugeMetricFamily(
            "opengauss_run_tpch_query_duration_seconds",
            "Duration of each TPCH query from run-scoped summary artifacts.",
            labels=["run", "scenario", "runner", "query_name"],
        )
        tpch_query_completed = GaugeMetricFamily(
            "opengauss_run_tpch_query_completed",
            "Whether a TPCH query completed and was recorded in run artifacts.",
            labels=["run", "scenario", "runner", "query_name"],
        )
        tpch_query_has_plan = GaugeMetricFamily(
            "opengauss_run_tpch_query_has_plan",
            "Whether a TPCH query has a captured plan artifact.",
            labels=["run", "scenario", "runner", "query_name"],
        )

        plan_count = GaugeMetricFamily(
            "opengauss_plan_analysis_plan_count",
            "Parsed execution plan count from offline plan-analysis artifacts.",
            labels=["run", "scenario", "analysis"],
        )
        plan_query_count = GaugeMetricFamily(
            "opengauss_plan_analysis_query_count",
            "Parsed query count from offline plan-analysis artifacts.",
            labels=["run", "scenario", "analysis"],
        )
        plan_operator_count = GaugeMetricFamily(
            "opengauss_plan_analysis_operator_count",
            "Parsed operator row count from offline plan-analysis artifacts.",
            labels=["run", "scenario", "analysis"],
        )
        plan_invalid_rows_total = GaugeMetricFamily(
            "opengauss_plan_analysis_invalid_rows_total",
            "Total invalid operator rows filtered or detected in plan-analysis artifacts.",
            labels=["run", "scenario", "analysis"],
        )
        query_execution_time = GaugeMetricFamily(
            "opengauss_plan_query_execution_time_ms",
            "Execution time per query from offline plan-analysis artifacts.",
            labels=["run", "scenario", "analysis", "query_name"],
        )
        query_max_exclusive_duration = GaugeMetricFamily(
            "opengauss_plan_query_max_exclusive_duration_ms",
            "Maximum exclusive operator duration per query from offline plan-analysis artifacts.",
            labels=["run", "scenario", "analysis", "query_name"],
        )
        query_max_exclusive_cost = GaugeMetricFamily(
            "opengauss_plan_query_max_exclusive_cost",
            "Maximum exclusive operator cost per query from offline plan-analysis artifacts.",
            labels=["run", "scenario", "analysis", "query_name"],
        )
        query_temp_written_blocks = GaugeMetricFamily(
            "opengauss_plan_query_temp_written_blocks",
            "Temporary written blocks per query from offline plan-analysis artifacts.",
            labels=["run", "scenario", "analysis", "query_name"],
        )
        query_external_sort_nodes = GaugeMetricFamily(
            "opengauss_plan_query_external_sort_nodes",
            "External sort node count per query from offline plan-analysis artifacts.",
            labels=["run", "scenario", "analysis", "query_name"],
        )
        plan_query_parse_ok = GaugeMetricFamily(
            "opengauss_plan_query_parse_ok",
            "Whether the query-level plan summary parsed successfully.",
            labels=["run", "scenario", "analysis", "query_name"],
        )
        plan_query_duration_sanity_ok = GaugeMetricFamily(
            "opengauss_plan_query_duration_sanity_ok",
            "Whether the query-level duration sanity status is healthy.",
            labels=["run", "scenario", "analysis", "query_name"],
        )
        plan_query_invalid_operator_count = GaugeMetricFamily(
            "opengauss_plan_query_invalid_operator_count",
            "Invalid operator row count per query from plan-analysis artifacts.",
            labels=["run", "scenario", "analysis", "query_name"],
        )
        operator_exclusive_duration_sum = GaugeMetricFamily(
            "opengauss_plan_operator_exclusive_duration_ms_sum",
            "Summed exclusive duration by operator node type from offline plan-analysis artifacts.",
            labels=["run", "scenario", "analysis", "node_type"],
        )
        operator_exclusive_cost_sum = GaugeMetricFamily(
            "opengauss_plan_operator_exclusive_cost_sum",
            "Summed exclusive cost by operator node type from offline plan-analysis artifacts.",
            labels=["run", "scenario", "analysis", "node_type"],
        )
        operator_sort_space_used_max = GaugeMetricFamily(
            "opengauss_plan_operator_sort_space_used_kb_max",
            "Maximum sort space usage by operator node type from offline plan-analysis artifacts.",
            labels=["run", "scenario", "analysis", "node_type"],
        )
        operator_temp_written_blocks_sum = GaugeMetricFamily(
            "opengauss_plan_operator_temp_written_blocks_sum",
            "Summed temporary written blocks by operator node type from offline plan-analysis artifacts.",
            labels=["run", "scenario", "analysis", "node_type"],
        )

        injection_start_epoch = GaugeMetricFamily(
            "opengauss_injection_start_epoch",
            "Injection start epoch captured for a run.",
            labels=["run", "scenario", "runner"],
        )
        injection_round_count = GaugeMetricFamily(
            "opengauss_injection_round_count",
            "Number of injection rounds captured for a run.",
            labels=["run", "scenario", "runner"],
        )
        injection_query_execution_time = GaugeMetricFamily(
            "opengauss_injection_query_execution_time_ms",
            "Execution time of injection queries by round and query.",
            labels=["run", "scenario", "runner", "round", "query_name"],
        )
        injection_query_temp_written = GaugeMetricFamily(
            "opengauss_injection_query_temp_written_blocks",
            "Temporary written blocks of injection queries by round and query.",
            labels=["run", "scenario", "runner", "round", "query_name"],
        )
        injection_query_external_sort_nodes = GaugeMetricFamily(
            "opengauss_injection_query_external_sort_nodes",
            "External sort node count of injection queries by round and query.",
            labels=["run", "scenario", "runner", "round", "query_name"],
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
            session_pressure_ratio,
            session_query_elapsed,
            shared_total,
            shared_free,
            shared_used,
            setting_bytes,
            setting_flag,
            execution_plan_queries,
            execution_plan_explain_count,
            execution_plan_normal_count,
            execution_plan_avg_duration,
            execution_plan_max_duration,
            validation_metric,
            sysbench_threads,
            sysbench_tps,
            sysbench_qps,
            sysbench_read_qps,
            sysbench_write_qps,
            sysbench_other_qps,
            sysbench_latency_p95,
            sysbench_errors,
            sysbench_reconnections,
            tpch_run_query_count,
            tpch_run_total_duration,
            tpch_run_avg_duration,
            tpch_run_max_duration,
            tpch_query_duration,
            tpch_query_completed,
            tpch_query_has_plan,
            plan_count,
            plan_query_count,
            plan_operator_count,
            plan_invalid_rows_total,
            query_execution_time,
            query_max_exclusive_duration,
            query_max_exclusive_cost,
            query_temp_written_blocks,
            query_external_sort_nodes,
            plan_query_parse_ok,
            plan_query_duration_sanity_ok,
            plan_query_invalid_operator_count,
            operator_exclusive_duration_sum,
            operator_exclusive_cost_sum,
            operator_sort_space_used_max,
            operator_temp_written_blocks_sum,
            injection_start_epoch,
            injection_round_count,
            injection_query_execution_time,
            injection_query_temp_written,
            injection_query_external_sort_nodes,
        ]

        overall_success = True

        try:
            logger.debug(f"Attempting to connect to {DB_HOST}:{DB_PORT}/{DB_NAME} as {DB_USER}")
            with connect() as conn:
                logger.debug("Connection successful")
                conn.autocommit = True
                with conn.cursor() as cursor:
                    for query_name, sql in QUERIES.items():
                        try:
                            rows = fetch_all(cursor, sql)
                            if query_name == "activity":
                                for datname, state, session_count in rows:
                                    activity_sessions.add_metric([str(datname), str(state)], float(session_count))
                            elif query_name == "temp_io":
                                for datname, temp_file_count, temp_byte_count in rows:
                                    temp_files.add_metric([str(datname)], float(temp_file_count))
                                    temp_bytes.add_metric([str(datname)], float(temp_byte_count))
                            elif query_name == "session_memory_pressure":
                                for datname, sessid, pid, usename, application_name, state, wait_event_type, total_b, free_b, used_b, used_ratio, query_age_seconds in rows:
                                    labels = [
                                        str(datname),
                                        str(sessid),
                                        str(pid),
                                        str(state),
                                        str(usename),
                                        str(application_name),
                                        str(wait_event_type),
                                    ]
                                    session_total.add_metric(labels, float(total_b))
                                    session_free.add_metric(labels, float(free_b))
                                    session_used.add_metric(labels, float(used_b))
                                    session_pressure_ratio.add_metric(labels, float(used_ratio))
                                    session_query_elapsed.add_metric(labels, float(query_age_seconds))
                            elif query_name == "shared_memory":
                                shared_by_context = defaultdict(
                                    lambda: {"total_bytes": 0.0, "free_bytes": 0.0, "used_bytes": 0.0}
                                )
                                for contextname, total_b, free_b, used_b in rows:
                                    context_key = str(contextname)
                                    aggregate = shared_by_context[context_key]
                                    aggregate["total_bytes"] += float(total_b)
                                    aggregate["free_bytes"] += float(free_b)
                                    aggregate["used_bytes"] += float(used_b)
                                for contextname, aggregate in sorted(shared_by_context.items()):
                                    labels = [contextname]
                                    shared_total.add_metric(labels, aggregate["total_bytes"])
                                    shared_free.add_metric(labels, aggregate["free_bytes"])
                                    shared_used.add_metric(labels, aggregate["used_bytes"])
                            elif query_name == "settings":
                                for name, value in rows:
                                    setting_bytes.add_metric([str(name)], float(value))
                            elif query_name == "setting_flags":
                                for name, value in rows:
                                    setting_flag.add_metric([str(name)], float(value))
                            elif query_name == "execution_plans":
                                for datname, query_type, query_count in rows:
                                    execution_plan_queries.add_metric([str(datname), str(query_type)], float(query_count))
                            elif query_name == "execution_plan_metrics":
                                for datname, explain_count, normal_count, avg_duration, max_duration in rows:
                                    execution_plan_explain_count.add_metric([str(datname)], float(explain_count))
                                    execution_plan_normal_count.add_metric([str(datname)], float(normal_count))
                                    execution_plan_avg_duration.add_metric([str(datname)], float(avg_duration) if avg_duration is not None else 0.0)
                                    execution_plan_max_duration.add_metric([str(datname)], float(max_duration) if max_duration is not None else 0.0)
                            query_success.add_metric([query_name], 1)
                        except Exception as exc:
                            logger.error(f"Query {query_name} failed: {exc}")
                            conn.rollback()
                            overall_success = False
                            query_success.add_metric([query_name], 0)
        except Exception as exc:
            logger.error(f"Connection failed: {exc}")
            overall_success = False
            for query_name in QUERIES:
                query_success.add_metric([query_name], 0)

        try:
            for summary_path in iter_validation_summary_files():
                run_dir = summary_path.parent
                run_id, scenario_name, runner = get_run_labels(run_dir)
                for metric_name, metric_value in parse_validation_summary(summary_path).items():
                    validation_metric.add_metric([run_id, scenario_name, runner, metric_name], metric_value)
            query_success.add_metric(["validation_summary_artifacts"], 1)
        except Exception as exc:
            logger.error(f"Validation summary artifact scan failed: {exc}")
            overall_success = False
            query_success.add_metric(["validation_summary_artifacts"], 0)

        try:
            for log_path in iter_sysbench_logs():
                run_dir = log_path.parent.parent
                run_id, scenario_name, runner = get_run_labels(run_dir)
                start_epoch = get_run_start_epoch(run_dir)
                finish_epoch = get_run_finish_epoch(run_dir)
                export_cutoff = time.time() - SYSBENCH_EXPORT_GRACE_SECONDS
                effective_end_epoch = finish_epoch if finish_epoch > 0 else start_epoch
                if effective_end_epoch > 0 and effective_end_epoch < export_cutoff:
                    continue
                for sample in parse_sysbench_log(log_path):
                    thread_label = str(int(sample["threads"]))
                    labels = [run_id, scenario_name, runner, thread_label]
                    timestamp = (start_epoch + sample["second"]) if start_epoch > 0 else None
                    sysbench_threads.add_metric(labels, sample["threads"], timestamp=timestamp)
                    sysbench_tps.add_metric(labels, sample["tps"], timestamp=timestamp)
                    sysbench_qps.add_metric(labels, sample["qps"], timestamp=timestamp)
                    sysbench_read_qps.add_metric(labels, sample["read_qps"], timestamp=timestamp)
                    sysbench_write_qps.add_metric(labels, sample["write_qps"], timestamp=timestamp)
                    sysbench_other_qps.add_metric(labels, sample["other_qps"], timestamp=timestamp)
                    sysbench_latency_p95.add_metric(labels, sample["latency_p95_ms"], timestamp=timestamp)
                    sysbench_errors.add_metric(labels, sample["errors_per_sec"], timestamp=timestamp)
                    sysbench_reconnections.add_metric(labels, sample["reconnections_per_sec"], timestamp=timestamp)
            query_success.add_metric(["sysbench_run_artifacts"], 1)
        except Exception as exc:
            logger.error(f"Sysbench run artifact scan failed: {exc}")
            overall_success = False
            query_success.add_metric(["sysbench_run_artifacts"], 0)

        try:
            for tpch_dir in iter_tpch_run_dirs():
                run_dir = tpch_dir.parent.parent
                run_id, scenario_name, runner = get_run_labels(run_dir)
                query_rows = build_tpch_query_rows(run_dir)
                query_count, total_duration, avg_duration, max_duration = summarize_tpch_rows(query_rows)
                aggregate_labels = [run_id, scenario_name]
                tpch_run_query_count.add_metric(aggregate_labels, float(query_count))
                tpch_run_total_duration.add_metric(aggregate_labels, total_duration)
                tpch_run_avg_duration.add_metric(aggregate_labels, avg_duration)
                tpch_run_max_duration.add_metric(aggregate_labels, max_duration)

                for row in query_rows:
                    labels = [run_id, scenario_name, runner, str(row["query_name"])]
                    tpch_query_duration.add_metric(labels, float(row["duration_seconds"]))
                    tpch_query_completed.add_metric(labels, float(row["completed"]))
                    tpch_query_has_plan.add_metric(labels, float(row["has_plan"]))
            query_success.add_metric(["tpch_run_artifacts"], 1)
        except Exception as exc:
            logger.error(f"TPCH run artifact scan failed: {exc}")
            overall_success = False
            query_success.add_metric(["tpch_run_artifacts"], 0)

        try:
            for analysis_dir in iter_plan_analysis_dirs():
                summary_path = analysis_dir / "grafana-summary.json"
                query_summary_path = analysis_dir / "query-summary.tsv"
                operator_summary_path = analysis_dir / "operator-summary.tsv"
                if not summary_path.exists() or not query_summary_path.exists() or not operator_summary_path.exists():
                    continue

                summary = read_json_file(summary_path)
                run_id, scenario_name, analysis_name = get_plan_labels(analysis_dir, summary)
                labels = [run_id, scenario_name, analysis_name]
                plan_count.add_metric(labels, safe_float(summary.get("plan_count")))
                plan_query_count.add_metric(labels, safe_float(summary.get("query_count")))
                plan_operator_count.add_metric(labels, safe_float(summary.get("operator_count")))

                invalid_rows_total = 0.0
                normalized_query_rows = load_plan_query_summary(query_summary_path)
                valid_query_names = {
                    str(normalized.get("query_name") or "")
                    for normalized in normalized_query_rows.values()
                    if safe_float(normalized.get("duration_ok")) > 0 and safe_float(normalized.get("parse_ok")) > 0
                }
                for normalized in normalized_query_rows.values():
                    query_labels = labels + [str(normalized.get("query_name") or "")]
                    invalid_count = safe_float(normalized.get("invalid_operator_count"))
                    invalid_rows_total += invalid_count
                    query_execution_time.add_metric(query_labels, safe_float(normalized.get("execution_time_ms")))
                    query_max_exclusive_duration.add_metric(query_labels, safe_float(normalized.get("max_exclusive_duration_ms")))
                    query_max_exclusive_cost.add_metric(query_labels, safe_float(normalized.get("max_exclusive_cost")))
                    query_temp_written_blocks.add_metric(query_labels, safe_float(normalized.get("temp_written_blocks")))
                    query_external_sort_nodes.add_metric(query_labels, safe_float(normalized.get("external_sort_nodes")))
                    plan_query_parse_ok.add_metric(query_labels, safe_float(normalized.get("parse_ok")))
                    plan_query_duration_sanity_ok.add_metric(query_labels, safe_float(normalized.get("duration_ok")))
                    plan_query_invalid_operator_count.add_metric(query_labels, invalid_count)
                plan_invalid_rows_total.add_metric(labels, invalid_rows_total)

                operator_rows = [
                    row for row in read_tsv_rows(operator_summary_path)
                    if not valid_query_names or str(row.get("query_name") or "") in valid_query_names
                ]
                operator_totals = defaultdict(
                    lambda: {
                        "exclusive_duration_ms_sum": 0.0,
                        "exclusive_cost_sum": 0.0,
                        "sort_space_used_kb_max": 0.0,
                        "temp_written_blocks_sum": 0.0,
                    }
                )
                for row in operator_rows:
                    node_type = str(row.get("node_type") or "unknown")
                    aggregate = operator_totals[node_type]
                    aggregate["exclusive_duration_ms_sum"] += safe_float(row.get("exclusive_duration_ms_sum"))
                    aggregate["exclusive_cost_sum"] += safe_float(row.get("exclusive_cost_sum"))
                    aggregate["sort_space_used_kb_max"] = max(
                        aggregate["sort_space_used_kb_max"],
                        safe_float(row.get("sort_space_used_kb_max")),
                    )
                    aggregate["temp_written_blocks_sum"] += safe_float(row.get("temp_written_blocks_sum"))

                for node_type, aggregate in sorted(operator_totals.items()):
                    operator_labels = labels + [node_type]
                    operator_exclusive_duration_sum.add_metric(operator_labels, aggregate["exclusive_duration_ms_sum"])
                    operator_exclusive_cost_sum.add_metric(operator_labels, aggregate["exclusive_cost_sum"])
                    operator_sort_space_used_max.add_metric(operator_labels, aggregate["sort_space_used_kb_max"])
                    operator_temp_written_blocks_sum.add_metric(operator_labels, aggregate["temp_written_blocks_sum"])
            query_success.add_metric(["plan_analysis_artifacts"], 1)
        except Exception as exc:
            logger.error(f"Plan analysis artifact scan failed: {exc}")
            overall_success = False
            query_success.add_metric(["plan_analysis_artifacts"], 0)

        try:
            for run_dir in iter_run_dirs():
                parsed = parse_injection_artifacts(run_dir)
                round_count = safe_float(parsed.get("round_count"))
                start_epoch = safe_float(parsed.get("start_epoch"))
                queries = parsed.get("queries") or []
                if round_count <= 0 and start_epoch <= 0 and not queries:
                    continue

                run_id, scenario_name, runner = get_run_labels(run_dir)
                base_labels = [run_id, scenario_name, runner]
                injection_start_epoch.add_metric(base_labels, start_epoch)
                injection_round_count.add_metric(base_labels, round_count)

                for query_row in queries:
                    query_labels = base_labels + [str(query_row.get("round") or ""), str(query_row.get("query_name") or "")]
                    injection_query_execution_time.add_metric(query_labels, safe_float(query_row.get("execution_time_ms")))
                    injection_query_temp_written.add_metric(query_labels, safe_float(query_row.get("temp_written_blocks")))
                    injection_query_external_sort_nodes.add_metric(query_labels, safe_float(query_row.get("external_sort_nodes")))
            query_success.add_metric(["injection_artifacts"], 1)
        except Exception as exc:
            logger.error(f"Injection artifact scan failed: {exc}")
            overall_success = False
            query_success.add_metric(["injection_artifacts"], 0)

        collection_success.add_metric([], 1 if overall_success else 0)
        collection_duration.add_metric([], time.time() - started)
        return families


if __name__ == "__main__":
    REGISTRY.register(OpenGaussCollector())
    start_http_server(EXPORTER_PORT)
    while True:
        time.sleep(60)
