#!/usr/bin/env python3
import csv
import pathlib
import sys

run_dir = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else pathlib.Path('experiments/runs')
for validation in run_dir.rglob('validation-summary.tsv'):
    rows = []
    with validation.open(encoding='utf-8', errors='ignore') as handle:
        reader = csv.reader(handle, delimiter='\t')
        next(reader, None)
        rows.extend(reader)
    print(validation)
    for key, value in rows:
        print(f'  {key}={value}')
