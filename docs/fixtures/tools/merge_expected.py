#!/usr/bin/env python3
"""Merges RECORDED_EXPECTED=<json> lines from `swift test` output into scores_cases.json."""
import json, sys, os
name = sys.argv[sys.argv.index('--file') + 1] if '--file' in sys.argv else 'scores_cases.json'
path = os.path.join(os.path.dirname(__file__), '..', name)
data = json.load(open(path))
rec = {}
for line in sys.stdin:
    if line.startswith('RECORDED_EXPECTED='):
        d = json.loads(line[len('RECORDED_EXPECTED='):])
        rec[d['name']] = d['expected']
for c in data['cases']:
    if c['name'] in rec: c['expected'] = rec[c['name']]
json.dump(data, open(path, 'w'), indent=1)
print('merged', len(rec))
