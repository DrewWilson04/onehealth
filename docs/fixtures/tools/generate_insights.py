#!/usr/bin/env python3
"""Generates docs/fixtures/insights_cases.json inputs (deterministic LCG noise).
Expected findings are recorded from PulseCore (RECORD_FIXTURES=1) via merge_expected.py --file insights_cases.json."""
import json, os, datetime as dt

class LCG:
    def __init__(self, seed): self.s = seed
    def next(self):
        self.s = (1103515245 * self.s + 12345) % 2**31
        return self.s / 2**31
    def normal(self):
        # Irwin–Hall approximation (sum of 12 uniforms − 6): deterministic & portable.
        return sum(self.next() for _ in range(12)) - 6

TODAY = dt.date(2024, 6, 30)
def day(k): return (TODAY - dt.timedelta(days=k)).isoformat()

def scenario_signal():
    r = LCG(42)
    steps, sleep, hrv, rhr, late, workout = {}, {}, {}, {}, {}, {}
    N = 90
    late_days = set()
    for k in range(N, -1, -1):
        d = day(k)
        is_late = (k % 4 == 0)
        st = 6000 + 4000 * r.next() + (2500 if k < 14 else 0)  # steps trend up in the last 2 weeks
        steps[d] = round(st)
        if is_late: late_days.add(k)
    for k in range(N, -1, -1):
        d = day(k)
        prev = k + 1
        base_sleep = 420 + 10 * r.normal()
        if prev <= N and steps.get(day(prev), 0) >= 8000: base_sleep += 35
        sleep[d] = round(base_sleep, 1)
        h = 52 + 3 * r.normal() - (9 if prev in late_days else 0)
        hrv[d] = round(h, 1)
        rhr[d] = round(56 + 1.2 * r.normal() + (9 if k == 0 else 0), 1)  # anomaly today
    workouts = [[day(k), 20 if k in late_days else 7] for k in range(N, -1, -1) if k in late_days or k % 7 == 3]
    return dict(name='signal: late workouts lower HRV, steps lengthen sleep, RHR anomaly, steps trend up',
                today=TODAY.isoformat(), series={'steps': steps, 'sleepMinutes': sleep, 'hrv': hrv, 'restingHeartRate': rhr},
                workouts=workouts)

def scenario_noise():
    r = LCG(7)
    steps, sleep, hrv, rhr = {}, {}, {}, {}
    for k in range(90, -1, -1):
        d = day(k)
        steps[d] = round(7000 + 3000 * r.next())
        sleep[d] = round(430 + 25 * r.normal(), 1)
        hrv[d] = round(50 + 5 * r.normal(), 1)
        rhr[d] = round(57 + 1.5 * r.normal(), 1)
    workouts = [[day(k), 20 if k % 5 == 0 else 8] for k in range(90, -1, -1) if k % 3 == 0]
    return dict(name='noise: no real effects', today=TODAY.isoformat(),
                series={'steps': steps, 'sleepMinutes': sleep, 'hrv': hrv, 'restingHeartRate': rhr}, workouts=workouts)

cases = [scenario_signal(), scenario_noise()]
path = os.path.join(os.path.dirname(__file__), '..', 'insights_cases.json')
old = {}
if os.path.exists(path):
    old = {c['name']: c.get('expected') for c in json.load(open(path))['cases']}
for c in cases:
    if old.get(c['name']) is not None: c['expected'] = old[c['name']]
json.dump({'description': 'Insights stats-engine fixtures. `series` are daily features (sleepMinutes keyed by wake day); `workouts` are [day, endHour]. Expected findings (ids + key numbers) recorded from PulseCore; web must match.',
           'tolerance': 0.01, 'cases': cases}, open(path, 'w'), indent=1)
print('wrote', len(cases))
