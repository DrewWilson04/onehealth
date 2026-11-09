import { describe, expect, it } from 'vitest';
import { close, fixture, toSample } from './fixtures';
import { compare, daily, direction, pctChange, personalBests, points, rollingAverage, rollup, streak, type Goal } from '../aggregate';
import { metric, type DailyAggregate } from '../model';
import { SourcePriority } from '../source';
import { UTC, addDays, ianaZone, isoWeekday, weekStart, dayStartMs, dayKeyOf } from '../daykey';
import { dailySummaryCSV, escapeCSV, csvNumber, samplesCSV } from '../csv';
import { activityBreakdown } from '../activityScore';

const agg = fixture('aggregation_cases.json');
function rows(d: Record<string, number>, id: string): DailyAggregate[] {
  const m = metric(id)!;
  return Object.entries(d).map(([day, v]) => (m.dailyStatistic === 'sum'
    ? { metric: id, period: 'day' as const, day, sum: v, count: 1, sourcePolicy: 'merged', isEstimated: false }
    : { metric: id, period: 'day' as const, day, average: v, min: v, max: v, latest: v, count: 1, sourcePolicy: 'merged', isEstimated: false }))
    .sort((a, b) => (a.day < b.day ? -1 : 1));
}

describe('aggregation fixtures', () => {
  it('steps rollups, rolling, comparison, bests', () => {
    const c = agg.steps, m = metric('steps')!;
    const d = rows(c.daily, 'steps');
    const w = rollup(d, m, 'week');
    expect(w.length).toBe(Object.keys(c.expectedWeekly).length);
    for (const r of w) {
      const e = c.expectedWeekly[r.day];
      expect(close(r.sum, e.sum)).toBe(true);
      expect(close(r.average, e.average)).toBe(true);
      expect(r.count).toBe(e.count);
    }
    const mo = rollup(d, m, 'month');
    expect(close(mo[0].sum, c.expectedMonthly['2024-03-01'].sum)).toBe(true);
    const roll = new Map(rollingAverage(points(d, m), 3, 3).map((p) => [p.day, p.value]));
    for (const [k, v] of Object.entries(c.expectedRolling3)) expect(close(roll.get(k), v as number)).toBe(true);
    expect(roll.has('2024-03-04')).toBe(false);
    const cmp = compare(d, m, 'week', c.today);
    expect(close(cmp.current, c.expectedWeekComparison.current)).toBe(true);
    expect(close(cmp.previous, c.expectedWeekComparison.previous)).toBe(true);
    expect(close(pctChange(cmp), c.expectedWeekComparison.percentChange)).toBe(true);
    expect(direction(cmp, true)).toBe(1);
    const b = personalBests(d, w, mo, m);
    expect(b.find((x) => x.period === 'day')).toMatchObject({ day: c.expectedBestDay.day, value: c.expectedBestDay.value });
    expect(b.find((x) => x.period === 'week')).toMatchObject({ day: c.expectedBestWeek.day, value: c.expectedBestWeek.value });
  });

  it('discrete rollup + lower-is-better best', () => {
    const c = agg.rhr, m = metric('restingHeartRate')!;
    const d = rows(c.daily, 'restingHeartRate');
    for (const r of rollup(d, m, 'week')) {
      expect(close(r.average, c.expectedWeekly[r.day].average)).toBe(true);
      expect(r.count).toBe(c.expectedWeekly[r.day].count);
    }
    const b = personalBests(d, [], [], m);
    expect(b.length).toBe(1);
    expect(b[0]).toMatchObject({ day: c.expectedBestDay.day, value: c.expectedBestDay.value });
  });

  it('rolling average skips gaps', () => {
    const c = agg.rollingGaps;
    const pts = Object.entries(c.points as Record<string, number>).map(([day, value]) => ({ day, value, isEstimated: false }));
    const r = rollingAverage(pts, c.window, c.minCount);
    expect(r.length).toBe(Object.keys(c.expected).length);
    for (const p of r) expect(close(c.expected[p.day], p.value)).toBe(true);
  });

  it('discrete daily from samples', () => {
    const dd = fixture('dedup_cases.json');
    const c = agg.discreteDaily;
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const r = daily(metric('heartRate')!, c.samples.map((s: any) => toSample(s, dd.sources)), { priority: new SourcePriority(), preferredSource: {}, zone: UTC });
    const e = c.expected['2024-03-10'];
    expect(r.length).toBe(1);
    expect(r[0]).toMatchObject({ average: e.average, min: e.min, max: e.max, latest: e.latest, count: e.count });
    expect(r[0].primarySource?.split('|')[0]).toBe(e.primarySource);
  });

  it('sleep + workout daily rows', () => {
    const dd = fixture('dedup_cases.json');
    const o = { priority: new SourcePriority(), preferredSource: {}, zone: UTC };
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const s = daily(metric('sleep')!, dd.sleep[0].samples.map((x: any) => toSample(x, dd.sources)), o);
    expect(s.length).toBe(1);
    expect(close(s[0].sum, 400)).toBe(true);
    expect(close(s[0].max, 495)).toBe(true);
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const w = daily(metric('workout')!, dd.workouts[0].samples.map((x: any) => toSample(x, dd.sources)), o);
    expect(w[0].count).toBe(2);
    expect(close(w[0].sum, 75)).toBe(true);
  });

  it('day keys match iOS', () => {
    expect(addDays('2024-02-28', 1)).toBe('2024-02-29');
    expect(weekStart('2024-03-13')).toBe('2024-03-11');
    expect(isoWeekday('2024-03-10')).toBe(7);
    const ny = ianaZone('America/New_York');
    expect(dayKeyOf(Date.parse('2024-03-10T12:00:00Z'), ny)).toBe('2024-03-10');
    expect(dayStartMs('2024-03-11', ny) - dayStartMs('2024-03-10', ny)).toBe(23 * 3600_000);
  });
});

describe('streak fixtures', () => {
  for (const c of fixture('streak_cases.json').cases) {
    it(c.name, () => {
      const g: Goal = { id: 'g', ...c.goal };
      const info = streak(g, metric(g.metric)!, new Map(Object.entries(c.daily as Record<string, number>)), c.today);
      expect(info.current).toBe(c.expected.current);
      expect(info.longest).toBe(c.expected.longest);
      expect(info.metCurrentPeriod).toBe(c.expected.metCurrentPeriod);
      if (c.expected.recent) expect(info.recent).toEqual(c.expected.recent);
    });
  }
});

describe('export fixtures', () => {
  const f = fixture('export_cases.json');
  it('daily summary CSV is byte-identical to iOS', () => {
    const ds = f.dailySummary;
    const map = new Map<string, DailyAggregate[]>();
    for (const r of ds.rows) {
      const list = map.get(r.metric) ?? [];
      list.push({ metric: r.metric, period: 'day', day: r.day, sum: r.sum, average: r.average, count: 1, sourcePolicy: 'merged', isEstimated: !!r.isEstimated });
      map.set(r.metric, list);
    }
    expect(dailySummaryCSV(ds.metrics.map((id: string) => metric(id)!), map, ds.from, ds.to)).toBe(ds.expected);
  });
  it('escaping and numbers', () => {
    for (const e of f.escaping) expect(escapeCSV(e.in)).toBe(e.out);
    for (const n of f.numbers) expect(csvNumber(n.in)).toBe(n.out);
  });
  it('samples CSV row', () => {
    const csv = samplesCSV([{ id: 'a', type: 'water', value: 250, unit: 'mL', start: 0, end: 0, source: { bundleId: 'b', name: 'My, App' }, isManual: true, isEstimated: false, metadata: { HKFoodType: 'Tea' } }]);
    expect(csv.split('\r\n')[1]).toBe('a,water,250,mL,1970-01-01T00:00:00Z,1970-01-01T00:00:00Z,"My, App",b,,true,false,HKFoodType=Tea');
  });
});

describe('activity score fixtures', () => {
  for (const c of fixture('activity_score_cases.json').cases) {
    it(c.name, () => {
      const i = c.inputs;
      const zones = Object.fromEntries(Object.entries(i.zoneMinutes ?? {}).map(([k, v]) => [Number(k), v as number]));
      const b = activityBreakdown({ steps: i.steps, exerciseMinutes: i.exerciseMinutes, zoneMinutes: zones, workoutMinutes: i.workoutMinutes, sleepMinutes: i.sleepMinutes });
      for (const k of ['steps', 'activeMinutes', 'intensity', 'sleep', 'total'] as const) expect(Math.abs(b[k] - c.expected[k])).toBeLessThan(0.011);
    });
  }
});
