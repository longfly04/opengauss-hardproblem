import os
import time
import logging
import sys
import re
from typing import Iterable, List, Dict

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    stream=sys.stdout
)
logger = logging.getLogger(__name__)

from prometheus_client import REGISTRY, start_http_server
from prometheus_client.core import GaugeMetricFamily

# Configuration
RUNS_DIR = os.getenv("RUNS_DIR", "/home/sducs/postgresql-dev/exp/opengauss-hardproblem/experiments/runs")
EXPORTER_PORT = int(os.getenv("LOG_EXPORTER_PORT", "9189"))
SCRAPE_INTERVAL = int(os.getenv("SCRAPE_INTERVAL", "5"))  # seconds

# Regex pattern to match sysbench run log lines
SYSBENCH_LOG_PATTERN = re.compile(
    r'\[\s*(\d+)s\s*\]\s*thds:\s*(\d+)\s*tps:\s*([\d.]+)\s*qps:\s*([\d.]+)\s*\(r/w/o:\s*([\d.]+)/([\d.]+)/([\d.]+)\)\s*lat\s*\(ms,95%\):\s*([\d.]+)\s*err/s:\s*([\d.]+)\s*reconn/s:\s*([\d.]+)'
)

# Regex pattern to extract experiment name from directory path
EXPERIMENT_NAME_PATTERN = re.compile(r'([^/]+)$')


def find_sysbench_run_logs() -> List[str]:
    """Find all sysbench-run.log files in the runs directory."""
    log_files = []
    for root, dirs, files in os.walk(RUNS_DIR):
        for file in files:
            if file == "sysbench-run.log":
                log_files.append(os.path.join(root, file))
    return log_files


def parse_sysbench_log(log_file: str) -> Dict[str, List[Dict]]:
    """Parse sysbench run log file and extract metrics."""
    metrics = []
    experiment_name = ""
    
    # Extract experiment name from directory path (get the parent of the 'tp' directory)
    log_dir = os.path.dirname(log_file)
    if 'tp' in log_dir:
        # Get the parent directory of 'tp'
        experiment_dir = os.path.dirname(log_dir)
        match = EXPERIMENT_NAME_PATTERN.search(experiment_dir)
        if match:
            experiment_name = match.group(1)
    else:
        # Fallback to original logic
        match = EXPERIMENT_NAME_PATTERN.search(log_dir)
        if match:
            experiment_name = match.group(1)
    
    try:
        with open(log_file, 'r') as f:
            for line in f:
                match = SYSBENCH_LOG_PATTERN.match(line.strip())
                if match:
                    data = {
                        "experiment": experiment_name,
                        "time": int(match.group(1)),
                        "threads": int(match.group(2)),
                        "tps": float(match.group(3)),
                        "qps": float(match.group(4)),
                        "read_qps": float(match.group(5)),
                        "write_qps": float(match.group(6)),
                        "other_qps": float(match.group(7)),
                        "latency_95": float(match.group(8)),
                        "errors_per_sec": float(match.group(9)),
                        "reconn_per_sec": float(match.group(10))
                    }
                    metrics.append(data)
    except Exception as e:
        logger.error(f"Error parsing log file {log_file}: {e}")
    
    return {"experiment": experiment_name, "metrics": metrics}


class SysbenchLogCollector:
    def collect(self) -> Iterable[GaugeMetricFamily]:
        started = time.time()
        
        # Define metric families
        collection_success = GaugeMetricFamily(
            "sysbench_log_exporter_last_collection_success",
            "Whether the last log collection succeeded.",
        )
        collection_duration = GaugeMetricFamily(
            "sysbench_log_exporter_last_collection_duration_seconds",
            "Duration of the last log collection in seconds.",
        )
        
        tps_metric = GaugeMetricFamily(
            "sysbench_tps",
            "Transactions per second from sysbench run logs.",
            labels=["experiment", "thread_count"]
        )
        
        qps_metric = GaugeMetricFamily(
            "sysbench_qps",
            "Queries per second from sysbench run logs.",
            labels=["experiment", "thread_count"]
        )
        
        read_qps_metric = GaugeMetricFamily(
            "sysbench_read_qps",
            "Read queries per second from sysbench run logs.",
            labels=["experiment", "thread_count"]
        )
        
        write_qps_metric = GaugeMetricFamily(
            "sysbench_write_qps",
            "Write queries per second from sysbench run logs.",
            labels=["experiment", "thread_count"]
        )
        
        other_qps_metric = GaugeMetricFamily(
            "sysbench_other_qps",
            "Other queries per second from sysbench run logs.",
            labels=["experiment", "thread_count"]
        )
        
        latency_95_metric = GaugeMetricFamily(
            "sysbench_latency_95pct",
            "95th percentile latency in milliseconds from sysbench run logs.",
            labels=["experiment", "thread_count"]
        )
        
        errors_metric = GaugeMetricFamily(
            "sysbench_errors_per_sec",
            "Errors per second from sysbench run logs.",
            labels=["experiment", "thread_count"]
        )
        
        reconn_metric = GaugeMetricFamily(
            "sysbench_reconn_per_sec",
            "Reconnections per second from sysbench run logs.",
            labels=["experiment", "thread_count"]
        )
        
        overall_success = True
        
        try:
            log_files = find_sysbench_run_logs()
            logger.info(f"Found {len(log_files)} sysbench run log files")
            
            for log_file in log_files:
                parsed_data = parse_sysbench_log(log_file)
                experiment = parsed_data.get("experiment", "unknown")
                metrics = parsed_data.get("metrics", [])
                
                if metrics:
                    # Use the latest metrics for each experiment
                    latest_metric = metrics[-1]
                    thread_count = str(latest_metric["threads"])
                    
                    tps_metric.add_metric([experiment, thread_count], latest_metric["tps"])
                    qps_metric.add_metric([experiment, thread_count], latest_metric["qps"])
                    read_qps_metric.add_metric([experiment, thread_count], latest_metric["read_qps"])
                    write_qps_metric.add_metric([experiment, thread_count], latest_metric["write_qps"])
                    other_qps_metric.add_metric([experiment, thread_count], latest_metric["other_qps"])
                    latency_95_metric.add_metric([experiment, thread_count], latest_metric["latency_95"])
                    errors_metric.add_metric([experiment, thread_count], latest_metric["errors_per_sec"])
                    reconn_metric.add_metric([experiment, thread_count], latest_metric["reconn_per_sec"])
                    
                    logger.debug(f"Processed metrics for experiment {experiment}")
                
        except Exception as e:
            logger.error(f"Error collecting log metrics: {e}")
            overall_success = False
        
        collection_success.add_metric([], 1 if overall_success else 0)
        collection_duration.add_metric([], time.time() - started)
        
        return [
            collection_success,
            collection_duration,
            tps_metric,
            qps_metric,
            read_qps_metric,
            write_qps_metric,
            other_qps_metric,
            latency_95_metric,
            errors_metric,
            reconn_metric
        ]


if __name__ == "__main__":
    REGISTRY.register(SysbenchLogCollector())
    start_http_server(EXPORTER_PORT)
    logger.info(f"Sysbench log exporter started on port {EXPORTER_PORT}")
    logger.info(f"Monitoring logs in directory: {RUNS_DIR}")
    
    while True:
        time.sleep(SCRAPE_INTERVAL)
