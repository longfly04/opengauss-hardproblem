#!/usr/bin/env python3
import argparse
import csv
import json
import subprocess
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

REPO_ROOT = Path(__file__).resolve().parents[2]
PEV2_DIR = REPO_ROOT / "ThirdParty" / "pev2"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Analyze benchmark execution plan files with the vendored PEV2 parser.")
    parser.add_argument("--input-dir", required=True, help="Directory containing .plan files")
    parser.add_argument("--output-dir", required=True, help="Directory to write structured analysis artifacts")
    parser.add_argument("--analysis-name", help="Logical analysis name for Grafana/exporter labels")
    parser.add_argument("--run-id", help="Run identifier to include in summary metadata")
    parser.add_argument("--scenario-name", help="Scenario name to include in summary metadata")
    return parser.parse_args()


def run_parser(input_dir: Path, output_dir: Path) -> Path:
    output_dir.mkdir(parents=True, exist_ok=True)
    jsonl_path = output_dir / "operator-nodes.jsonl"
    cmd = [
        "npm",
        "run",
        "parse-plan",
        "--",
        "--input-dir",
        str(input_dir),
        "--output-dir",
        str(output_dir),
        "--format",
        "jsonl",
    ]
    subprocess.run(cmd, cwd=PEV2_DIR, check=True)
    return jsonl_path


def read_rows(jsonl_path: Path) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    with jsonl_path.open("r", encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if not line:
                continue
            rows.append(json.loads(line))
    return rows


def write_tsv(path: Path, fieldnames: list[str], rows: list[dict[str, Any]]) -> None:
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames, delimiter="\t", extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)


def to_number(value: Any) -> float:
    if value is None or value == "":
        return 0.0
    if isinstance(value, bool):
        return float(int(value))
    return float(value)


def is_duration_row_valid(row: dict[str, Any]) -> bool:
    duration_sanity_ok = row.get("duration_sanity_ok")
    if isinstance(duration_sanity_ok, str) and duration_sanity_ok.strip():
        normalized = duration_sanity_ok.strip().lower()
        if normalized in {"false", "0", "no"}:
            return False
    elif duration_sanity_ok is False:
        return False

    limit = row.get("duration_sanity_limit_ms")
    actual_total = row.get("actual_total_time_ms")
    exclusive_duration = row.get("exclusive_duration_ms")
    limit_value = to_number(limit)
    if limit_value <= 0:
        return True

    for value in (actual_total, exclusive_duration):
        numeric = to_number(value)
        if numeric > limit_value:
            return False
    return True


def build_query_summary(rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    grouped: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for row in rows:
        grouped[str(row["query_name"])].append(row)

    summaries: list[dict[str, Any]] = []
    for query_name, query_rows in sorted(grouped.items()):
        valid_rows = [row for row in query_rows if is_duration_row_valid(row)]
        summary_runtime = max(to_number(row.get("plan_execution_time_ms")) for row in query_rows)
        runtime_source = "plan_footer" if summary_runtime > 0 else "node_max_actual_total"
        runtime_value = summary_runtime
        if runtime_value <= 0:
            runtime_value = max(to_number(row.get("actual_total_time_ms")) for row in valid_rows or query_rows)

        rows_for_aggregation = valid_rows or query_rows
        root = min(rows_for_aggregation, key=lambda item: int(item.get("depth") or 0))
        external_sort_count = sum(1 for row in rows_for_aggregation if row.get("sort_space_type") == "Disk")
        invalid_operator_count = len(query_rows) - len(valid_rows)
        summaries.append(
            {
                "query_name": query_name,
                "root_node_type": root.get("node_type") or "",
                "plan_execution_time_ms": runtime_value,
                "max_exclusive_duration_ms": max(to_number(row.get("exclusive_duration_ms")) for row in rows_for_aggregation),
                "max_exclusive_cost": max(to_number(row.get("exclusive_cost")) for row in rows_for_aggregation),
                "max_sort_space_used_kb": max(to_number(row.get("sort_space_used_kb")) for row in rows_for_aggregation),
                "sum_temp_written_blocks": sum(to_number(row.get("temp_written_blocks")) for row in rows_for_aggregation),
                "sum_temp_read_blocks": sum(to_number(row.get("temp_read_blocks")) for row in rows_for_aggregation),
                "sum_io_read_time_ms": sum(to_number(row.get("sum_io_read_time_ms")) for row in rows_for_aggregation),
                "sum_io_write_time_ms": sum(to_number(row.get("sum_io_write_time_ms")) for row in rows_for_aggregation),
                "external_sort_node_count": external_sort_count,
                "runtime_source": runtime_source,
                "duration_sanity_status": "ok" if invalid_operator_count == 0 else "filtered_invalid_rows",
                "invalid_operator_count": invalid_operator_count,
                "parse_status": "ok",
            }
        )
    return summaries


def build_operator_summary(rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    filtered_rows = [row for row in rows if is_duration_row_valid(row)] or rows
    grouped: dict[tuple[str, str], list[dict[str, Any]]] = defaultdict(list)
    for row in filtered_rows:
        grouped[(str(row["query_name"]), str(row.get("node_type") or "unknown"))].append(row)

    summaries: list[dict[str, Any]] = []
    for (query_name, node_type), group_rows in sorted(grouped.items()):
        summaries.append(
            {
                "query_name": query_name,
                "node_type": node_type,
                "operator_count": len(group_rows),
                "exclusive_duration_ms_sum": sum(to_number(row.get("exclusive_duration_ms")) for row in group_rows),
                "exclusive_duration_ms_max": max(to_number(row.get("exclusive_duration_ms")) for row in group_rows),
                "exclusive_cost_sum": sum(to_number(row.get("exclusive_cost")) for row in group_rows),
                "sort_space_used_kb_max": max(to_number(row.get("sort_space_used_kb")) for row in group_rows),
                "temp_written_blocks_sum": sum(to_number(row.get("temp_written_blocks")) for row in group_rows),
                "io_read_time_ms_sum": sum(to_number(row.get("sum_io_read_time_ms")) for row in group_rows),
            }
        )
    return summaries


def build_top(rows: list[dict[str, Any]], metric: str, limit: int = 20) -> list[dict[str, Any]]:
    filtered_rows = [row for row in rows if is_duration_row_valid(row)] or rows
    sorted_rows = sorted(filtered_rows, key=lambda row: to_number(row.get(metric)), reverse=True)
    result: list[dict[str, Any]] = []
    for rank, row in enumerate(sorted_rows[:limit], start=1):
        result.append(
            {
                "rank": rank,
                "query_name": row.get("query_name") or "",
                "plan_file": row.get("plan_file") or "",
                "node_id": row.get("node_id") or "",
                "node_type": row.get("node_type") or "",
                metric: to_number(row.get(metric)),
            }
        )
    return result


def main() -> None:
    args = parse_args()
    input_dir = Path(args.input_dir).resolve()
    output_dir = Path(args.output_dir).resolve()

    jsonl_path = run_parser(input_dir, output_dir)
    rows = read_rows(jsonl_path)

    if not rows:
        raise SystemExit("no parsed operator rows found")

    write_tsv(
        output_dir / "query-summary.tsv",
        [
            "query_name",
            "root_node_type",
            "plan_execution_time_ms",
            "max_exclusive_duration_ms",
            "max_exclusive_cost",
            "max_sort_space_used_kb",
            "sum_temp_written_blocks",
            "sum_temp_read_blocks",
            "sum_io_read_time_ms",
            "sum_io_write_time_ms",
            "external_sort_node_count",
            "runtime_source",
            "duration_sanity_status",
            "invalid_operator_count",
            "parse_status",
        ],
        build_query_summary(rows),
    )

    write_tsv(
        output_dir / "operator-summary.tsv",
        [
            "query_name",
            "node_type",
            "operator_count",
            "exclusive_duration_ms_sum",
            "exclusive_duration_ms_max",
            "exclusive_cost_sum",
            "sort_space_used_kb_max",
            "temp_written_blocks_sum",
            "io_read_time_ms_sum",
        ],
        build_operator_summary(rows),
    )

    write_tsv(
        output_dir / "top-operators-duration.tsv",
        ["rank", "query_name", "plan_file", "node_id", "node_type", "exclusive_duration_ms"],
        build_top(rows, "exclusive_duration_ms"),
    )

    write_tsv(
        output_dir / "top-operators-cost.tsv",
        ["rank", "query_name", "plan_file", "node_id", "node_type", "exclusive_cost"],
        build_top(rows, "exclusive_cost"),
    )

    write_tsv(
        output_dir / "top-operators-memory.tsv",
        ["rank", "query_name", "plan_file", "node_id", "node_type", "sort_space_used_kb"],
        build_top(rows, "sort_space_used_kb"),
    )

    summary = {
        "analysis_name": args.analysis_name or output_dir.name,
        "source_input_dir": str(input_dir),
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "run_id": args.run_id,
        "scenario_name": args.scenario_name,
        "plan_count": len({str(row["plan_file"]) for row in rows}),
        "operator_count": len(rows),
        "query_count": len({str(row["query_name"]) for row in rows}),
    }
    (output_dir / "grafana-summary.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
