#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"

missing=0
for cmd in bash sed awk grep date; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    printf 'missing required command: %s\n' "$cmd" >&2
    missing=1
  fi
done

if ! command -v docker >/dev/null 2>&1; then
  printf 'missing required command: docker\n' >&2
  missing=1
fi

if command -v docker >/dev/null 2>&1; then
  if ! docker compose version >/dev/null 2>&1 && ! command -v docker-compose >/dev/null 2>&1; then
    printf 'missing docker compose plugin or docker-compose binary\n' >&2
    missing=1
  fi
fi

for optional in git curl python3 java mvn; do
  if ! command -v "$optional" >/dev/null 2>&1; then
    printf 'optional command not found: %s\n' "$optional"
  fi
done

printf 'repo root: %s\n' "$REPO_ROOT"
printf 'compose env template: %s\n' "$REPO_ROOT/env/compose/.env.example"
printf 'docker-first mode: enabled\n'

exit "$missing"
