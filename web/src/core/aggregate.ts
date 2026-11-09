// Mirror of PulseCore Aggregator + Trends + Streaks.
import type { DailyAggregate, MetricType, Sample } from './model';
import { aggValue, attribution } from './model';
import { SourcePriority } from './source';
import { binByDay, dedupeCumulative, mergeWorkouts, selectDiscrete, sleepNights, sweepSegments, nightEfficiency } from './dedup';
import { type DayKey, type Zone, addDays, dayKeyOf, daysBetween, isoWeekday, localHour, monthStart, range, weekStart, yearStart } from './daykey';

export interface AggOptions { priority: SourcePriority; preferredSource: Record<string, string>; zone: Zone }

const isSumStat = (m: MetricType) => m.dailyStatistic === 'sum' || m.dailyStatistic === 'durationMinutes' || m.dailyStatistic === 'count';
const byDayKey = (a: { day: DayKey }, b: { day: DayKey }) => (a.day < b.day ? -1 : a.day > b.day ? 1 : 0);

export function daily(m: MetricType, samples: Sample[], o: AggOptions): DailyAggregate[] {
  const pref = o.preferredSource[m.id];
  const priority = o.priority.preferring(pref);
  const policy = pref ? `pref:${pref}` : 'merged';
  const ofType = samples.filter((s) => s.type === m.id);
  if (!ofType.length) return [];
  switch (m.kind) {
    case 'cumulative': {
      const segs = dedupeCumulative(ofType, priority);
      const bins = binByDay(segs, o.zone);
      const src = new Map<DayKey, Map<string, number>>();
      const est = new Set<DayKey>();
      for (const s of segs) {
        const k = dayKeyOf(s.start, o.zone);
        const mp = src.get(k) ?? new Map();
        mp.set(attribution(s.source), (mp.get(attribution(s.source)) ?? 0) + s.value);
        src.set(k, mp);
        if (s.isEstimated) est.add(k);
      }
      return [...bins].map(([day, sum]) => {
        let primary: string | undefined, best = -Infinity;
        for (const [k, v] of src.get(day) ?? []) if (v > best) { best = v; primary = k; }
        return { metric: m.id, period: 'day' as const, day, sum, count: 1, primarySource: primary, sourcePolicy: policy, isEstimated: est.has(day) };
      }).sort(byDayKey);
    }
    case 'discrete': case 'ecg': {
      const groups = new Map<DayKey, Sample[]>();
      for (const s of ofType) { const k = dayKeyOf(s.start, o.zone); (groups.get(k) ?? groups.set(k, []).get(k)!).push(s); }
      const out: DailyAggregate[] = [];
      for (const [day, list] of groups) {
        const chosen = selectDiscrete(list, pref, priority);
        if (!chosen.length) continue;
        const vals = chosen.map((s) => s.value);
        const latest = chosen.reduce((a, b) => (b.end > a.end ? b : a)).value;
        const sum = vals.reduce((a, b) => a + b, 0);
        out.push({ metric: m.id, period: 'day', day, sum, average: sum / vals.length, min: Math.min(...vals), max: Math.max(...vals), latest,
          count: vals.length, primarySource: attribution(chosen[0].source), sourcePolicy: policy, isEstimated: chosen.some((s) => s.isEstimated) });
      }
      return out.sort(byDayKey);
    }
    case 'category': {
      if (m.id === 'sleep') {
        return sleepNights(ofType, priority, o.zone).map((n) => ({
          metric: 'sleep', period: 'day' as const, day: n.day, sum: n.asleepMinutes, average: nightEfficiency(n) !== undefined ? nightEfficiency(n)! * 100 : undefined,
          max: n.inBedMinutes, count: 1, primarySource: attribution(n.primarySource), sourcePolicy: policy, isEstimated: n.isEstimated,
        }));
      }
      const byDay = new Map<DayKey, { min: number; count: number }>();
      const get = (d: DayKey) => byDay.get(d) ?? byDay.set(d, { min: 0, count: 0 }).get(d)!;
      if (m.id === 'standHour') {
        const slots = new Set<string>();
        for (const s of ofType) if (s.value === 0) {
          const d = dayKeyOf(s.start, o.zone), h = localHour(s.start, o.zone);
          if (!slots.has(`${d}-${h}`)) { slots.add(`${d}-${h}`); get(d).count++; }
        }
      } else {
        const segs = sweepSegments(ofType, priority);
        for (const s of segs) { const e = get(dayKeyOf(s.start, o.zone)); e.min += (s.end - s.start) / 60000; e.count++; }
        if (!segs.length) for (const s of ofType) get(dayKeyOf(s.start, o.zone)).count++;
      }
      return [...byDay].map(([day, v]) => ({ metric: m.id, period: 'day' as const, day, sum: m.dailyStatistic === 'count' ? v.count : v.min,
        count: v.count, sourcePolicy: policy, isEstimated: false })).sort(byDayKey);
    }
    case 'workout': {
      const merged = mergeWorkouts(ofType, priority);
      const groups = new Map<DayKey, Sample[]>();
      for (const w of merged) { const k = dayKeyOf(w.start, o.zone); (groups.get(k) ?? groups.set(k, []).get(k)!).push(w); }
      return [...groups].map(([day, list]) => {
        const energy = list.reduce((t, w) => t + (w.metadata?.energyKcal ? Number(w.metadata.energyKcal) : 0), 0);
        return { metric: 'workout', period: 'day' as const, day, sum: list.reduce((t, w) => t + w.value, 0), average: energy > 0 ? energy : undefined,
          count: list.length, primarySource: attribution(list[0].source), sourcePolicy: policy, isEstimated: list.some((w) => w.isEstimated) };
      }).sort(byDayKey);
    }
  }
}

export function rollup(dailyRows: DailyAggregate[], m: MetricType, period: 'week' | 'month' | 'year'): DailyAggregate[] {
  const key = (d: DayKey) => (period === 'week' ? weekStart(d) : period === 'month' ? monthStart(d) : yearStart(d));
  const groups = new Map<DayKey, DailyAggregate[]>();
  for (const r of dailyRows.filter((r) => r.period === 'day')) (groups.get(key(r.day)) ?? groups.set(key(r.day), []).get(key(r.day))!).push(r);
  const out: DailyAggregate[] = [];
  for (const [start, rows] of groups) {
    rows.sort(byDayKey);
    const est = rows.some((r) => r.isEstimated);
    const counts = new Map<string, number>();
    for (const r of rows) if (r.primarySource) counts.set(r.primarySource, (counts.get(r.primarySource) ?? 0) + 1);
    let src: string | undefined, best = -1;
    for (const [k, v] of counts) if (v > best) { best = v; src = k; }
    if (isSumStat(m)) {
      const vals = rows.map((r) => aggValue(r, m.dailyStatistic)).filter((v): v is number => v !== undefined);
      const total = vals.reduce((a, b) => a + b, 0);
      out.push({ metric: m.id, period, day: start, sum: total, average: vals.length ? total / vals.length : undefined, min: vals.length ? Math.min(...vals) : undefined,
        max: vals.length ? Math.max(...vals) : undefined, latest: vals[vals.length - 1], count: vals.length, primarySource: src, sourcePolicy: rows[0].sourcePolicy, isEstimated: est });
    } else {
      const avgs = rows.map((r) => r.average ?? r.latest).filter((v): v is number => v !== undefined);
      const mins = rows.map((r) => r.min ?? r.average).filter((v): v is number => v !== undefined);
      const maxs = rows.map((r) => r.max ?? r.average).filter((v): v is number => v !== undefined);
      const last = rows[rows.length - 1];
      out.push({ metric: m.id, period, day: start, average: avgs.length ? avgs.reduce((a, b) => a + b, 0) / avgs.length : undefined,
        min: mins.length ? Math.min(...mins) : undefined, max: maxs.length ? Math.max(...maxs) : undefined, latest: last.latest ?? last.average,
        count: avgs.length, primarySource: src, sourcePolicy: rows[0].sourcePolicy, isEstimated: est });
    }
  }
  return out.sort(byDayKey);
}

// ── Trends ──────────────────────────────────────────────────────────────

export type TrendRange = 'D' | 'W' | 'M' | '6M' | 'Y' | 'All';
export const RANGE_DAYS: Record<TrendRange, number | undefined> = { D: 1, W: 7, M: 30, '6M': 182, Y: 365, All: undefined };
export const RANGE_BUCKET: Record<TrendRange, 'hour' | 'day' | 'week' | 'month'> = { D: 'hour', W: 'day', M: 'day', '6M': 'week', Y: 'month', All: 'month' };

export interface TrendPoint { day: DayKey; hour?: number; value: number; min?: number; max?: number; isEstimated: boolean }

export const points = (rows: DailyAggregate[], m: MetricType): TrendPoint[] =>
  rows.map((r) => ({ r, v: aggValue(r, m.dailyStatistic) })).filter((x) => x.v !== undefined)
    .map(({ r, v }) => ({ day: r.day, hour: r.hour, value: v!, min: r.min, max: r.max, isEstimated: r.isEstimated }))
    .sort((a, b) => (a.day === b.day ? (a.hour ?? 0) - (b.hour ?? 0) : a.day < b.day ? -1 : 1));

export function rollupPoints(rows: DailyAggregate[], m: MetricType, perDayAverage: boolean): TrendPoint[] {
  return rows.map((r): TrendPoint | undefined => {
    let v: number | undefined;
    if (isSumStat(m)) v = perDayAverage ? r.average : r.sum;
    else if (m.dailyStatistic === 'average') v = r.average;
    else v = r.latest ?? r.average;
    return v === undefined ? undefined : { day: r.day, value: v, min: r.min, max: r.max, isEstimated: r.isEstimated };
  }).filter((p): p is TrendPoint => !!p).sort(byDayKey);
}

export interface TrendSummary { average?: number; total?: number; min?: number; max?: number; daysWithData: number }
export function summary(rows: DailyAggregate[], m: MetricType): TrendSummary {
  const vals = rows.map((r) => aggValue(r, m.dailyStatistic)).filter((v): v is number => v !== undefined);
  if (!vals.length) return { daysWithData: 0 };
  const total = vals.reduce((a, b) => a + b, 0);
  return { average: total / vals.length, total: isSumStat(m) ? total : undefined, min: Math.min(...vals), max: Math.max(...vals), daysWithData: vals.length };
}

export function rollingAverage(pts: TrendPoint[], window: number, minCount?: number): TrendPoint[] {
  const need = minCount ?? Math.max(1, Math.floor(window / 2));
  if (!pts.length) return [];
  const by = new Map<DayKey, number>();
  for (const p of pts) if (!by.has(p.day)) by.set(p.day, p.value);
  const days = pts.map((p) => p.day).sort();
  const first = days[0], last = days[days.length - 1];
  const out: TrendPoint[] = [];
  for (const d of range(first, last)) {
    let sum = 0, n = 0;
    for (let k = 0; k < window; k++) { const v = by.get(addDays(d, -k)); if (v !== undefined) { sum += v; n++; } }
    if ((n >= need && by.has(d)) || (n >= need && d === last)) out.push({ day: d, value: sum / n, isEstimated: false });
  }
  return out;
}

export interface PeriodComparison { current?: number; previous?: number; currentDays: number; previousDays: number }
export const pctChange = (c: PeriodComparison) => (c.current !== undefined && c.previous !== undefined && c.previous !== 0 ? (c.current - c.previous) / Math.abs(c.previous) : undefined);
export function direction(c: PeriodComparison, higherIsBetter: boolean | null): number {
  const p = pctChange(c);
  if (c.current === undefined || c.previous === undefined || higherIsBetter === null || p === undefined || Math.abs(p) < 0.02) return 0;
  return (c.current - c.previous > 0) === higherIsBetter ? 1 : -1;
}

export function compare(rows: DailyAggregate[], m: MetricType, period: 'week' | 'month' | 'year', today: DayKey): PeriodComparison {
  let start: DayKey, prevStart: DayKey;
  if (period === 'week') { start = weekStart(today); prevStart = addDays(start, -7); }
  else if (period === 'month') {
    start = monthStart(today);
    const [y, mo] = start.split('-').map(Number);
    prevStart = `${mo === 1 ? y - 1 : y}-${String(mo === 1 ? 12 : mo - 1).padStart(2, '0')}-01`;
  } else { start = yearStart(today); prevStart = `${Number(start.slice(0, 4)) - 1}-01-01`; }
  const elapsed = daysBetween(start, today);
  const prevEnd = addDays(prevStart, elapsed);
  const by = new Map(rows.filter((r) => r.period === 'day').map((r) => [r.day, r]));
  const mean = (a: DayKey, b: DayKey): [number | undefined, number] => {
    const vals = range(a, b).map((d) => (by.get(d) ? aggValue(by.get(d)!, m.dailyStatistic) : undefined)).filter((v): v is number => v !== undefined);
    return [vals.length ? vals.reduce((x, y) => x + y, 0) / vals.length : undefined, vals.length];
  };
  const [c, cn] = mean(start, today), [p, pn] = mean(prevStart, prevEnd);
  return { current: c, previous: p, currentDays: cn, previousDays: pn };
}

export interface PersonalBest { day: DayKey; value: number; period: 'day' | 'week' | 'month' }
export function personalBests(dailyRows: DailyAggregate[], weekly: DailyAggregate[], monthly: DailyAggregate[], m: MetricType): PersonalBest[] {
  if (m.higherIsBetter === null) return [];
  const hib = m.higherIsBetter;
  const best = (rows: DailyAggregate[], period: PersonalBest['period'], useSum: boolean): PersonalBest | undefined => {
    let pick: PersonalBest | undefined;
    for (const r of rows) {
      if (r.isEstimated) continue;
      const v = useSum ? r.sum : (r.average ?? r.latest);
      if (v === undefined) continue;
      if (!pick || (hib ? v > pick.value : v < pick.value)) pick = { day: r.day, value: v, period };
    }
    return pick;
  };
  const isSum = isSumStat(m);
  const out: PersonalBest[] = [];
  const d = best(dailyRows, 'day', isSum); if (d) out.push(d);
  if (isSum) { const w = best(weekly, 'week', true); if (w) out.push(w); const mo = best(monthly, 'month', true); if (mo) out.push(mo); }
  return out;
}

// ── Goals & streaks ─────────────────────────────────────────────────────

export interface Goal { id: string; metric: string; target: number; period: 'day' | 'week'; direction: 'atLeast' | 'atMost' }
export const goalMet = (g: Goal, v?: number) => v !== undefined && (g.direction === 'atLeast' ? v >= g.target : v <= g.target);
export function goalProgress(g: Goal, v?: number): number {
  if (v === undefined || g.target <= 0) return 0;
  return g.direction === 'atLeast' ? v / g.target : v <= g.target ? 1 : Math.max(0, 1 - (v - g.target) / g.target);
}

export interface StreakInfo { current: number; longest: number; metCurrentPeriod: boolean; currentValue?: number; progress: number; recent: boolean[] }

export function streak(g: Goal, m: MetricType, dailyValues: Map<DayKey, number>, today: DayKey): StreakInfo {
  let step: (d: DayKey) => DayKey, value: (d: DayKey) => number | undefined, start: DayKey;
  if (g.period === 'day') { step = (d) => addDays(d, -1); value = (d) => dailyValues.get(d); start = today; }
  else {
    const isSum = isSumStat(m);
    step = (d) => addDays(d, -7);
    value = (ws) => {
      const vals = [0, 1, 2, 3, 4, 5, 6].map((i) => dailyValues.get(addDays(ws, i))).filter((v): v is number => v !== undefined);
      if (!vals.length) return undefined;
      const t = vals.reduce((a, b) => a + b, 0);
      return isSum ? t : t / vals.length;
    };
    start = weekStart(today);
  }
  const cv = value(start);
  const metNow = goalMet(g, cv);
  let current = metNow ? 1 : 0;
  let c = step(start);
  while (goalMet(g, value(c))) { current++; c = step(c); }
  let longest = 0, run = 0, seen = false;
  c = start;
  for (let i = 0; i < 366 * 10; i++) {
    const v = value(c);
    if (v !== undefined) seen = true;
    if (goalMet(g, v)) { run++; longest = Math.max(longest, run); } else if (c !== start) run = 0;
    c = step(c);
    if (!seen && daysBetween(c, start) > 400) break;
  }
  longest = Math.max(longest, current);
  const recent: boolean[] = [];
  let r = start;
  for (let i = 0; i < 7; i++) { recent.push(goalMet(g, value(r))); r = step(r); }
  return { current, longest, metCurrentPeriod: metNow, currentValue: cv, progress: goalProgress(g, cv), recent: recent.reverse() };
}

export const DEFAULT_GOALS: Goal[] = [
  { id: 'default.steps', metric: 'steps', target: 8000, period: 'day', direction: 'atLeast' },
  { id: 'default.sleep', metric: 'sleep', target: 450, period: 'day', direction: 'atLeast' },
  { id: 'default.exercise', metric: 'exerciseTime', target: 30, period: 'day', direction: 'atLeast' },
  { id: 'default.water', metric: 'water', target: 2000, period: 'day', direction: 'atLeast' },
];

export { isoWeekday };
