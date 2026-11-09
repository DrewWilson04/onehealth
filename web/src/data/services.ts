// UI-side services: settings, scores and patterns computed from IndexedDB.
import { aggregates, intraday, samples, type ImportInfo } from '../db/queries';
import { getMeta, setMeta } from '../db/db';
import { type DayKey, LOCAL, addDays, dayKeyOf, dayStartMs, keyToEpochDay, range } from '../core/daykey';
import { aggValue, metric, sourceKey, type DailyAggregate } from '../core/model';
import { SourcePriority } from '../core/source';
import { mergeWorkouts, sleepNights, type SleepNight } from '../core/dedup';
import { computeAll, trimp, estimateMaxHR, baseline, type HRPoint, type ScoreInputs, type ScoreKind, type ScoreResult } from '../core/scores';
import { DEFAULT_GOALS, type Goal } from '../core/aggregate';
import { runInsights, withWorkoutFlags, type Features, type Finding } from '../core/insights';

export interface Settings { priority: string[]; preferred: Record<string, string>; goals: Goal[]; sleepGoalMinutes: number }
const DEFAULT_SETTINGS: Settings = { priority: [], preferred: {}, goals: DEFAULT_GOALS, sleepGoalMinutes: 480 };

export async function loadSettings(): Promise<Settings> {
  return { ...DEFAULT_SETTINGS, ...((await getMeta<Settings>('settings')) ?? {}) };
}
export const saveSettings = (s: Settings) => setMeta('settings', s);
export const loadImportInfo = () => getMeta<ImportInfo>('import');

/** "Today" for a snapshot = the export day (data isn't live). */
export function snapshotDay(info?: ImportInfo): DayKey {
  const exportDay = info?.exportDate ? dayKeyOf(info.exportDate, LOCAL) : undefined;
  if (exportDay && info?.lastDay) return info.lastDay < exportDay ? info.lastDay : exportDay;
  return exportDay ?? info?.lastDay ?? dayKeyOf(Date.now(), LOCAL);
}

export async function nights(from: DayKey, to: DayKey, s: Settings): Promise<SleepNight[]> {
  const ss = await samples('sleep', dayStartMs(addDays(from, -1), LOCAL), dayStartMs(addDays(to, 1), LOCAL));
  return sleepNights(ss, new SourcePriority(s.priority).preferring(s.preferred.sleep), LOCAL).filter((n) => n.day >= from && n.day <= to);
}

function hrFromIntraday(hr: (number | null)[], day: DayKey): HRPoint[] {
  const start = dayStartMs(day, LOCAL);
  const out: HRPoint[] = [];
  hr.forEach((v, i) => { if (v !== null) out.push({ time: start + i * 60_000, bpm: v }); });
  return out;
}

function ageOn(info: ImportInfo | undefined, day: DayKey) {
  const dob = info?.me.dateOfBirth;
  if (!dob) return undefined;
  return (dayStartMs(day, LOCAL) - Date.parse(dob)) / (365.25 * 86_400_000);
}
const sexOf = (info?: ImportInfo): ScoreInputs['sex'] => {
  const s = info?.me.biologicalSex;
  return s === 'HKBiologicalSexFemale' ? 'female' : s === 'HKBiologicalSexMale' ? 'male' : s === 'HKBiologicalSexOther' ? 'other' : 'unknown';
};

async function buildInputs(day: DayKey, info: ImportInfo | undefined, s: Settings, intradayToo: boolean): Promise<ScoreInputs> {
  const from = addDays(day, -31);
  const hrvSamples = await samples('hrv', dayStartMs(from, LOCAL) - 4 * 3600_000, dayStartMs(addDays(day, 1), LOCAL));
  const any: Record<string, Map<DayKey, number[]>> = {}, night: Record<string, Map<DayKey, number[]>> = {};
  for (const x of hrvSamples) {
    if (x.isEstimated) continue;
    const k = dayKeyOf(x.start, LOCAL), src = sourceKey(x.source);
    const push = (o: Record<string, Map<DayKey, number[]>>, d: DayKey) => {
      const m = o[src] ?? (o[src] = new Map());
      (m.get(d) ?? m.set(d, []).get(d)!).push(x.value);
    };
    push(any, k);
    const h = new Date(x.start).getHours();
    if (h >= 20) push(night, addDays(k, 1)); else if (h < 10) push(night, k);
  }
  const hrvBySource: Record<string, Map<DayKey, number>> = {};
  for (const src of Object.keys(any)) {
    const m = new Map<DayKey, number>();
    const avg = (v: number[]) => v.reduce((a, b) => a + b, 0) / v.length;
    for (const [d, v] of any[src]) m.set(d, avg(v));
    for (const [d, v] of night[src] ?? []) m.set(d, avg(v));
    hrvBySource[src] = new Map([...m].filter(([d]) => d >= from && d <= day));
  }
  const rhrRows = await aggregates('restingHeartRate', 'day', from, day);
  const restingHR = new Map(rhrRows.filter((r) => !r.isEstimated && (r.average ?? r.latest) !== undefined).map((r) => [r.day, (r.average ?? r.latest)!]));
  const ns = await nights(addDays(day, -9), day, s);
  const nightMap = new Map(ns.map((n) => [n.day, n]));
  let heartRate: HRPoint[] = [], steps: [number, number][] = [], workouts: [number, number][] = [];
  const loadHistory = new Map<DayKey, number>();
  let observedMaxHR: number | undefined;
  if (intradayToo) {
    const it = await intraday(day);
    if (it) {
      heartRate = hrFromIntraday(it.hr, day);
      const st = dayStartMs(day, LOCAL);
      steps = it.steps.map((v, i) => [st + i * 900_000, v] as [number, number]).filter(([, v]) => v > 0);
    }
    const w = await samples('workout', dayStartMs(day, LOCAL), dayStartMs(addDays(day, 1), LOCAL));
    workouts = w.map((x) => [x.start, x.end]);
    const months = await aggregates('heartRate', 'month', addDays(day, -365), day);
    const maxes = months.map((m) => m.max).filter((v): v is number => v !== undefined);
    observedMaxHR = maxes.length ? Math.max(...maxes) : undefined;
    // Load history from cached intraday HR (last 28 days).
    const rest = baseline(restingHR, day, 30, 3)?.mean;
    if (rest) {
      const prof = { maxHR: estimateMaxHR(ageOn(info, day), undefined), restingHR: rest, sex: sexOf(info) };
      for (let k = 1; k <= 28; k++) {
        const d = addDays(day, -k);
        const x = await intraday(d);
        if (!x) continue;
        const pts = hrFromIntraday(x.hr, d);
        if (pts.length >= 10) loadHistory.set(d, trimp(pts, prof));
      }
    }
  }
  const end = dayStartMs(addDays(day, 1), LOCAL);
  return {
    day, zone: LOCAL, hrvBySource, preferredHRVSource: s.preferred.hrv, restingHR, nights: nightMap, sleepGoalMinutes: s.sleepGoalMinutes,
    heartRate, steps, workouts, loadHistory, age: ageOn(info, day), sex: sexOf(info), observedMaxHR,
    now: info?.exportDate ? Math.min(info.exportDate, end) : end,
  };
}

export async function scoresFor(day: DayKey, info: ImportInfo | undefined, s: Settings): Promise<Record<ScoreKind, ScoreResult>> {
  return computeAll(await buildInputs(day, info, s, true));
}

export async function scoreHistory(kind: ScoreKind, from: DayKey, to: DayKey, info: ImportInfo | undefined, s: Settings): Promise<ScoreResult[]> {
  const out: ScoreResult[] = [];
  const heavy = kind === 'strain' || kind === 'energy';
  for (const d of range(from, to)) out.push((computeAll(await buildInputs(d, info, s, heavy)))[kind]);
  return out;
}

export async function patterns(today: DayKey, s: Settings): Promise<Finding[]> {
  const from = addDays(today, -135);
  const f: Features = {};
  for (const id of ['steps', 'activeEnergy', 'exerciseTime', 'restingHeartRate', 'hrv', 'respiratoryRate', 'wristTemperature', 'bodyMass', 'vo2Max', 'caffeine']) {
    const m = metric(id)!;
    const rows = await aggregates(id, 'day', from, today);
    f[id] = new Map(rows.filter((r) => !r.isEstimated).map((r) => [r.day, aggValue(r, m.dailyStatistic)]).filter((x): x is [DayKey, number] => x[1] !== undefined));
  }
  const ns = await nights(from, today, s);
  f.sleepMinutes = new Map(ns.filter((n) => !n.isEstimated).map((n) => [n.day, n.asleepMinutes]));
  f.bedtimeAfter18 = new Map(ns.map((n) => {
    const onset = n.segments.find((x) => [1, 3, 4, 5].includes(x.value))?.start ?? n.start;
    const d = new Date(onset);
    return [n.day, (((d.getHours() + 24 - 18) % 24) * 60) + d.getMinutes()];
  }));
  const ws = mergeWorkouts(await samples('workout', dayStartMs(from, LOCAL), dayStartMs(addDays(today, 1), LOCAL)), new SourcePriority(s.priority));
  const withFlags = withWorkoutFlags(f, ws.filter((w) => !w.isEstimated).map((w) => ({ day: dayKeyOf(w.start, LOCAL), endHour: new Date(w.end).getHours() })));
  return runInsights(withFlags, today);
}

export function valueOf(a: DailyAggregate | undefined, id: string) {
  const m = metric(id);
  return a && m ? aggValue(a, m.dailyStatistic) : undefined;
}

export const daysAgo = (a: DayKey, b: DayKey) => keyToEpochDay(b) - keyToEpochDay(a);
