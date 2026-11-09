// Mirror of PulseCore Scores + Gaps (see /docs/scores.md).
import type { Confidence } from './model';
import { type SleepNight, nightEfficiency, sleepOnset, wakeTime } from './dedup';
import { type DayKey, type Zone, addDays, daysBetween, dayStartMs, localMinuteOfDay } from './daykey';

export type ScoreKind = 'readiness' | 'sleep' | 'strain' | 'energy';
export interface ScoreComponent { name: string; score: number; weight: number; raw?: number; baseline?: number; isEstimated: boolean }
export interface ScoreResult {
  kind: ScoreKind; day: DayKey; value?: number; components: ScoreComponent[]; inputsUsed: string[]; missingInputs: string[];
  confidence: Confidence; isEstimated: boolean; reason?: string; extras: Record<string, number>; series?: number[];
}

const CONF_ORDER: Record<Confidence, number> = { low: 0, medium: 1, high: 2 };
const minConf = (...c: Confidence[]) => c.reduce((a, b) => (CONF_ORDER[a] <= CONF_ORDER[b] ? a : b));
const logistic = (x: number) => 1 / (1 + Math.exp(-x));
const clamp = (x: number, lo = 0, hi = 100) => Math.min(hi, Math.max(lo, x));
const mean = (x: number[]) => (x.length ? x.reduce((a, b) => a + b, 0) / x.length : 0);
const sd = (x: number[]) => {
  if (x.length < 2) return 0;
  const m = mean(x);
  return Math.sqrt(x.reduce((t, v) => t + (v - m) ** 2, 0) / (x.length - 1));
};
const round1 = (v: number) => Math.round(v * 10) / 10;

function insufficient(kind: ScoreKind, day: DayKey, reason: string, missing: string[], used: string[] = []): ScoreResult {
  return { kind, day, components: [], inputsUsed: used, missingInputs: missing, confidence: 'low', isEstimated: false, reason, extras: {} };
}

type Part = { name: string; score?: number; weight: number; raw?: number; baseline?: number; est: boolean };
function combine(parts: Part[]): [number | undefined, ScoreComponent[]] {
  const present = parts.filter((p) => p.score !== undefined);
  const total = present.reduce((t, p) => t + p.weight, 0);
  if (total <= 0) return [undefined, []];
  const comps = present.map((p) => ({ name: p.name, score: p.score!, weight: p.weight / total, raw: p.raw, baseline: p.baseline, isEstimated: p.est }));
  return [comps.reduce((t, c) => t + c.score * c.weight, 0), comps];
}

// ── Baselines & gaps ────────────────────────────────────────────────────

export interface Baseline { mean: number; sd: number; count: number }
export function baseline(values: Map<DayKey, number>, before: DayKey, window = 30, minDays = 10, log = false): Baseline | undefined {
  const xs: number[] = [];
  for (let k = 1; k <= window; k++) {
    const v = values.get(addDays(before, -k));
    if (v !== undefined && (v > 0 || !log)) xs.push(log ? Math.log(v) : v);
  }
  return xs.length >= minDays ? { mean: mean(xs), sd: sd(xs), count: xs.length } : undefined;
}

export interface FilledValue { value: number; isEstimated: boolean; confidence?: Confidence }
export function fillDaily(measured: Map<DayKey, number>, from: DayKey, through: DayKey, maxGap = 2): Map<DayKey, FilledValue> {
  const out = new Map<DayKey, FilledValue>();
  for (const [k, v] of measured) if (k >= from && k <= through) out.set(k, { value: v, isEstimated: false });
  for (let day = from; day <= through; day = addDays(day, 1)) {
    if (measured.has(day)) continue;
    let back = 1, last: number | undefined;
    while (back <= maxGap) { const v = measured.get(addDays(day, -back)); if (v !== undefined) { last = v; break; } back++; }
    const base = baseline(measured, day, 30, 7);
    if (last === undefined || !base) continue;
    const w = back === 1 ? 0.5 : 0.25;
    const cv = base.mean !== 0 ? base.sd / Math.abs(base.mean) : 1;
    const conf: Confidence = back === 1 && cv < 0.1 ? 'high' : cv < 0.25 ? 'medium' : 'low';
    out.set(day, { value: w * last + (1 - w) * base.mean, isEstimated: true, confidence: back === 1 ? conf : minConf(conf, 'medium') });
  }
  return out;
}

export function fillSeries(points: [number, number][], step = 900_000, maxGap = 3 * 3600_000): [number, number, boolean][] {
  const s = [...points].sort((a, b) => a[0] - b[0]);
  const out: [number, number, boolean][] = [];
  s.forEach((p, i) => {
    out.push([p[0], p[1], false]);
    if (i + 1 >= s.length) return;
    const n = s[i + 1], gap = n[0] - p[0];
    if (gap <= step * 1.5 || gap > maxGap) return;
    for (let t = p[0] + step; t < n[0] - step / 2; t += step) out.push([t, p[1] + ((n[1] - p[1]) * (t - p[0])) / gap, true]);
  });
  return out;
}

// ── Sleep Score ─────────────────────────────────────────────────────────

export const durationScore = (asleep: number, goal: number) => {
  const r = asleep / Math.max(goal, 1);
  if (r > 1.3) return clamp(100 - (r - 1.3) * 100, 70, 100);
  return 100 * Math.min(1, r) ** 1.5;
};
export const efficiencyScore = (e: number) => clamp(((e - 0.7) / 0.25) * 100);
export function circularSDMinutes(times: number[], z: Zone): number {
  const angles = times.map((t) => (localMinuteOfDay(t, z) / 1440) * 2 * Math.PI);
  const s = angles.reduce((t, a) => t + Math.sin(a), 0) / angles.length;
  const c = angles.reduce((t, a) => t + Math.cos(a), 0) / angles.length;
  const r = Math.max(1e-9, Math.min(1, Math.sqrt(s * s + c * c)));
  return (Math.sqrt(-2 * Math.log(r)) / (2 * Math.PI)) * 1440;
}
export function consistencyScore(nights: SleepNight[], z: Zone): [number, number] | undefined {
  const recent = nights.slice(-7);
  if (recent.length < 3) return undefined;
  const sdv = (circularSDMinutes(recent.map(sleepOnset), z) + circularSDMinutes(recent.map(wakeTime), z)) / 2;
  return [clamp(100 - (sdv - 15) * (100 / 75)), sdv];
}
export function bandScore(p: number, lo: number, hi: number) {
  if (p >= lo && p <= hi) return 100;
  return p < lo ? clamp(100 * (1 - (lo - p) / 10)) : clamp(100 * (1 - (p - hi) / 15));
}
export function stageScore(n: SleepNight): number | undefined {
  if (!n.hasStages || n.asleepMinutes <= 0) return undefined;
  const deep = ((n.stageMinutes[4] ?? 0) / n.asleepMinutes) * 100;
  const rem = ((n.stageMinutes[5] ?? 0) / n.asleepMinutes) * 100;
  return (bandScore(deep, 13, 23) + bandScore(rem, 20, 25)) / 2;
}

export function sleepScore(day: DayKey, night: SleepNight | undefined, previous: SleepNight[], goal: number, z: Zone): ScoreResult {
  if (!night || night.asleepMinutes < 60) return insufficient('sleep', day, 'No sleep recorded last night.', ['Sleep']);
  const used = ['Sleep duration'], missing: string[] = [];
  const eff = nightEfficiency(night);
  if (eff !== undefined) used.push('Time in bed'); else missing.push('Time in bed');
  const cons = consistencyScore([...previous, night], z);
  if (cons) used.push('Bed/wake consistency'); else missing.push('3+ nights for consistency');
  const st = stageScore(night);
  if (st !== undefined) used.push('Sleep stages'); else missing.push('Sleep stages');
  const [value, comps] = combine([
    { name: 'Duration', score: durationScore(night.asleepMinutes, goal), weight: 0.4, raw: night.asleepMinutes, baseline: goal, est: night.isEstimated },
    { name: 'Efficiency', score: eff !== undefined ? efficiencyScore(eff) : undefined, weight: 0.2, raw: eff !== undefined ? eff * 100 : undefined, est: false },
    { name: 'Consistency', score: cons?.[0], weight: 0.2, raw: cons?.[1], est: false },
    { name: 'Stages', score: st, weight: 0.2, est: false },
  ]);
  const conf: Confidence = comps.length >= 4 ? 'high' : comps.length >= 3 ? 'medium' : 'low';
  return { kind: 'sleep', day, value: value !== undefined ? round1(value) : undefined, components: comps, inputsUsed: used, missingInputs: missing,
    confidence: night.isEstimated ? minConf(conf, 'medium') : conf, isEstimated: night.isEstimated, extras: {} };
}

// ── Readiness ───────────────────────────────────────────────────────────

export const hrvScore = (z: number) => 100 * logistic(0.6 + 1.2 * z);
export const rhrScore = (z: number) => 100 * logistic(0.6 - 1.2 * z);

export function readinessScore(day: DayKey, i: { hrv: Map<DayKey, number>; hrvTodayFilled?: FilledValue; rhr: Map<DayKey, number>; rhrTodayFilled?: FilledValue; sleep?: ScoreResult }): ScoreResult {
  const used: string[] = [], missing: string[] = [];
  let estimated = false, worst: Confidence = 'high';
  let hrvP: Part = { name: 'HRV', weight: 0.4, est: false };
  const hb = baseline(i.hrv, day, 30, 10, true);
  const ht = i.hrv.has(day) ? { value: i.hrv.get(day)!, isEstimated: false } as FilledValue : i.hrvTodayFilled;
  if (hb && ht && ht.value > 0) {
    const z = (Math.log(ht.value) - hb.mean) / Math.max(hb.sd, 0.1);
    hrvP = { name: 'HRV', score: hrvScore(z), weight: 0.4, raw: ht.value, baseline: Math.exp(hb.mean), est: ht.isEstimated };
    used.push('HRV vs 30-day baseline');
    if (ht.isEstimated) { estimated = true; worst = minConf(worst, ht.confidence ?? 'low'); }
  } else missing.push(hb ? "Last night's HRV" : '10+ days of HRV');
  let rhrP: Part = { name: 'Resting HR', weight: 0.25, est: false };
  const rb = baseline(i.rhr, day);
  const rt = i.rhr.has(day) ? { value: i.rhr.get(day)!, isEstimated: false } as FilledValue : i.rhrTodayFilled;
  if (rb && rt) {
    const z = (rt.value - rb.mean) / Math.max(rb.sd, 2);
    rhrP = { name: 'Resting HR', score: rhrScore(z), weight: 0.25, raw: rt.value, baseline: rb.mean, est: rt.isEstimated };
    used.push('Resting HR vs 30-day baseline');
    if (rt.isEstimated) { estimated = true; worst = minConf(worst, rt.confidence ?? 'low'); }
  } else missing.push(rb ? "Today's resting HR" : '10+ days of resting HR');
  if (hrvP.score === undefined && rhrP.score === undefined) {
    return insufficient('readiness', day, 'Readiness needs at least 10 days of HRV or resting heart rate, plus today\'s reading.', missing, used);
  }
  if (i.sleep?.value !== undefined) { used.push('Sleep Score'); if (i.sleep.isEstimated) estimated = true; } else missing.push("Last night's sleep");
  const [value, comps] = combine([hrvP, rhrP, { name: 'Sleep', score: i.sleep?.value, weight: 0.35, raw: i.sleep?.value, est: i.sleep?.isEstimated ?? false }]);
  let conf: Confidence = comps.length === 3 ? 'high' : comps.length === 2 ? 'medium' : 'low';
  if (estimated) conf = minConf(conf, worst, 'medium');
  return { kind: 'readiness', day, value: value !== undefined ? round1(value) : undefined, components: comps, inputsUsed: used, missingInputs: missing,
    confidence: conf, isEstimated: estimated, extras: {} };
}

// ── Strain ──────────────────────────────────────────────────────────────

export interface HRPoint { time: number; bpm: number }
export interface HRProfile { maxHR: number; restingHR: number; sex: 'female' | 'male' | 'other' | 'unknown' }
export function estimateMaxHR(age?: number, observed?: number): number {
  if (age !== undefined) {
    const t = 208 - 0.7 * age;
    return observed !== undefined ? Math.min(Math.max(t, observed), t + 15) : t;
  }
  return Math.min(220, Math.max(160, observed ?? 190));
}
export const hrr = (p: HRProfile, bpm: number) => clamp((bpm - p.restingHR) / Math.max(1, p.maxHR - p.restingHR), 0, 1);
export function zone(p: HRProfile, bpm: number) {
  const r = hrr(p, bpm);
  return r < 0.5 ? 0 : r < 0.6 ? 1 : r < 0.7 ? 2 : r < 0.8 ? 3 : r < 0.9 ? 4 : 5;
}
const coeff = (p: HRProfile) => (p.sex === 'female' ? [0.86, 1.67] : [0.64, 1.92]);

export function trimp(points: HRPoint[], p: HRProfile): number {
  const s = [...points].sort((a, b) => a.time - b.time);
  if (s.length < 2) return 0;
  const [k1, k2] = coeff(p);
  let total = 0;
  for (let i = 1; i < s.length; i++) {
    const dt = Math.min(5, (s[i].time - s[i - 1].time) / 60_000);
    if (dt <= 0) continue;
    const x = hrr(p, (s[i].bpm + s[i - 1].bpm) / 2);
    if (x < 0.25) continue;
    total += dt * x * k1 * Math.exp(k2 * x);
  }
  return total;
}
export function zoneMinutes(points: HRPoint[], p: HRProfile): Record<number, number> {
  const s = [...points].sort((a, b) => a.time - b.time);
  const out: Record<number, number> = {};
  for (let i = 1; i < s.length; i++) {
    const dt = Math.min(5, (s[i].time - s[i - 1].time) / 60_000);
    const z = zone(p, (s[i].bpm + s[i - 1].bpm) / 2);
    if (z > 0 && dt > 0) out[z] = (out[z] ?? 0) + dt;
  }
  return out;
}
export const strainFromTRIMP = (t: number) => clamp((21 * Math.log(1 + t / 20)) / Math.log(21), 0, 21);
export function acwr(load: Map<DayKey, number>, day: DayKey) {
  const a = [...Array(7).keys()].map((k) => load.get(addDays(day, -k))).filter((v): v is number => v !== undefined);
  const c = [...Array(28).keys()].map((k) => load.get(addDays(day, -k))).filter((v): v is number => v !== undefined);
  if (a.length < 4 || c.length < 14) return undefined;
  const am = mean(a), cm = mean(c);
  return cm > 0 ? { acute: am, chronic: cm, ratio: am / cm } : undefined;
}
export function loadStatus(r?: number) {
  if (r === undefined) return 'Building your baseline';
  return r < 0.8 ? 'Below your usual load' : r < 1.3 ? 'In your optimal range' : r < 1.5 ? 'Load is climbing' : 'Much higher than usual';
}

export function strainScore(day: DayKey, hr: HRPoint[], profile: HRProfile | undefined, history: Map<DayKey, number>): ScoreResult {
  if (!profile) return insufficient('strain', day, 'Strain needs a resting heart rate.', ['Resting HR']);
  if (hr.length < 10) return insufficient('strain', day, 'Not enough heart-rate data today.', ['Heart rate']);
  const t = trimp(hr, profile);
  const load = new Map(history);
  load.set(day, t);
  const r = acwr(load, day);
  const extras: Record<string, number> = { trimp: t, maxHR: profile.maxHR, restingHR: profile.restingHR };
  if (r) { extras.acute = r.acute; extras.chronic = r.chronic; extras.acwr = r.ratio; }
  for (const [z, m] of Object.entries(zoneMinutes(hr, profile))) extras[`zone${z}`] = m;
  const used = [`Heart rate (${hr.length} readings)`, `Heart-rate zones from max ${Math.trunc(profile.maxHR)} / rest ${Math.trunc(profile.restingHR)} bpm`];
  const missing: string[] = [];
  if (r) used.push('28-day load history'); else missing.push('14+ days of load history for training balance');
  return { kind: 'strain', day, value: round1(strainFromTRIMP(t)), components: [], inputsUsed: used, missingInputs: missing,
    confidence: hr.length >= 100 ? 'high' : hr.length >= 40 ? 'medium' : 'low', isEstimated: false, reason: r ? loadStatus(r.ratio) : undefined, extras };
}

// ── Energy ──────────────────────────────────────────────────────────────

export interface EnergySlot { start: number; avgHR?: number; steps: number; inWorkout: boolean; asleep: boolean; estimatedHR: boolean }
const SLOT = 900_000;
export const energyStart = (sleep: number, hrvSub?: number) => clamp(20 + 0.8 * (hrvSub !== undefined ? 0.6 * sleep + 0.4 * hrvSub : sleep));

export function simulateEnergy(start: number, slots: EnergySlot[], p: HRProfile) {
  let e = start, drained = 0, charged = 0;
  const series: number[] = [];
  const [k1, k2] = coeff(p);
  for (const s of slots) {
    let d = 0;
    if (s.asleep) d += 1.5 * (1 - e / 100);
    else {
      d -= 0.15;
      if (s.avgHR !== undefined) {
        const x = hrr(p, s.avgHR);
        if (x >= 0.25) d -= 0.25 * 15 * x * k1 * Math.exp(k2 * x);
        else if (s.steps < 50 && !s.inWorkout) {
          const over = s.avgHR - p.restingHR - 15;
          if (over > 0) d -= Math.min(2, 0.08 * over);
          else if (s.avgHR <= p.restingHR + 5) d += 0.3;
        }
      }
    }
    if (d < 0) drained -= d; else charged += d;
    e = clamp(e + d);
    series.push(round1(e));
  }
  return { end: e, series, drained, charged };
}

export function energySlots(from: number, to: number, hr: HRPoint[], steps: [number, number][], workouts: [number, number][], sleep: [number, number][], fill = true): EnergySlot[] {
  if (to <= from) return [];
  const n = Math.ceil((to - from) / SLOT);
  const hrSum = new Array(n).fill(0), hrN = new Array(n).fill(0), st = new Array(n).fill(0);
  for (const p of hr) { const i = Math.floor((p.time - from) / SLOT); if (i >= 0 && i < n) { hrSum[i] += p.bpm; hrN[i]++; } }
  for (const [d, v] of steps) { const i = Math.floor((d - from) / SLOT); if (i >= 0 && i < n) st[i] += v; }
  const raw: [number, number][] = [];
  for (let i = 0; i < n; i++) if (hrN[i] > 0) raw.push([from + i * SLOT, hrSum[i] / hrN[i]]);
  const filled = fill ? fillSeries(raw, SLOT) : raw.map(([a, b]) => [a, b, false] as [number, number, boolean]);
  const by = new Map<number, [number, boolean]>();
  for (const [d, v, est] of filled) { const i = Math.round((d - from) / SLOT); if (i >= 0 && i < n) by.set(i, [v, est]); }
  const within = (iv: [number, number][], t: number) => iv.some(([a, b]) => t >= a && t <= b);
  return [...Array(n).keys()].map((i) => {
    const t = from + i * SLOT, mid = t + SLOT / 2;
    return { start: t, avgHR: by.get(i)?.[0], steps: st[i], inWorkout: within(workouts, mid), asleep: within(sleep, mid), estimatedHR: by.get(i)?.[1] ?? false };
  });
}

export function energyScore(day: DayKey, sleep: ScoreResult | undefined, hrvSub: number | undefined, slots: EnergySlot[], profile: HRProfile | undefined): ScoreResult {
  if (sleep?.value === undefined) return insufficient('energy', day, "Energy starts from last night's recovery — no sleep recorded.", ['Sleep']);
  if (!profile) return insufficient('energy', day, 'Energy needs a resting heart rate baseline.', ['Resting HR']);
  const withHR = slots.filter((s) => s.avgHR !== undefined);
  const coverage = slots.length ? withHR.length / slots.length : 0;
  if (coverage < 0.25) return insufficient('energy', day, 'Not enough heart-rate data today to estimate energy.', ['Daytime heart rate'], ['Sleep Score']);
  const start = energyStart(sleep.value, hrvSub);
  const r = simulateEnergy(start, slots, profile);
  const estimated = slots.some((s) => s.estimatedHR) || sleep.isEstimated;
  const used = ['Sleep Score'], missing: string[] = [];
  if (hrvSub !== undefined) used.push('Overnight HRV'); else missing.push('Overnight HRV');
  if (withHR.length) used.push('Daytime heart rate'); else missing.push('Daytime heart rate');
  if (slots.some((s) => s.steps > 0)) used.push('Steps');
  let conf: Confidence = coverage > 0.7 ? 'high' : coverage > 0.35 ? 'medium' : 'low';
  if (estimated) conf = minConf(conf, 'medium');
  return { kind: 'energy', day, value: round1(r.end), components: [], inputsUsed: used, missingInputs: missing, confidence: conf, isEstimated: estimated,
    extras: { start: round1(start), drained: r.drained, charged: r.charged }, series: r.series };
}

// ── Engine ──────────────────────────────────────────────────────────────

export interface ScoreInputs {
  day: DayKey; zone: Zone; hrvBySource: Record<string, Map<DayKey, number>>; preferredHRVSource?: string; restingHR: Map<DayKey, number>;
  nights: Map<DayKey, SleepNight>; sleepGoalMinutes: number; heartRate: HRPoint[]; steps: [number, number][]; workouts: [number, number][];
  loadHistory: Map<DayKey, number>; age?: number; sex: HRProfile['sex']; observedMaxHR?: number; now: number;
}

export function hrvSource(i: ScoreInputs): string | undefined {
  if (i.preferredHRVSource && i.hrvBySource[i.preferredHRVSource]?.size) return i.preferredHRVSource;
  let best: [string, number] | undefined;
  for (const [k, m] of Object.entries(i.hrvBySource)) {
    const c = [...m.keys()].filter((d) => daysBetween(d, i.day) <= 30).length;
    if (!best || c > best[1] || (c === best[1] && k < best[0])) best = [k, c];
  }
  return best?.[0];
}

export function profileFor(i: ScoreInputs): HRProfile | undefined {
  const rest = baseline(i.restingHR, i.day, 30, 3)?.mean ?? i.restingHR.get(i.day);
  if (rest === undefined) return undefined;
  return { maxHR: estimateMaxHR(i.age, i.observedMaxHR), restingHR: rest, sex: i.sex };
}

export function computeAll(i: ScoreInputs): Record<ScoreKind, ScoreResult> {
  const d = i.day;
  const prev = [1, 2, 3, 4, 5, 6, 7].map((k) => i.nights.get(addDays(d, -k))).filter((n): n is SleepNight => !!n).sort((a, b) => (a.day < b.day ? -1 : 1));
  const sleep = sleepScore(d, i.nights.get(d), prev, i.sleepGoalMinutes, i.zone);
  const src = hrvSource(i);
  const hrv = (src ? i.hrvBySource[src] : undefined) ?? new Map<DayKey, number>();
  const hrvFill = hrv.has(d) ? undefined : fillDaily(hrv, d, d).get(d);
  const rhrFill = i.restingHR.has(d) ? undefined : fillDaily(i.restingHR, d, d).get(d);
  const readiness = readinessScore(d, { hrv, hrvTodayFilled: hrvFill, rhr: i.restingHR, rhrTodayFilled: rhrFill, sleep: sleep.value === undefined ? undefined : sleep });
  const prof = profileFor(i);
  const strain = strainScore(d, i.heartRate, prof, i.loadHistory);
  const dayStart = dayStartMs(d, i.zone);
  const night = i.nights.get(d);
  const wake = night ? wakeTime(night) : dayStart;
  const end = Math.min(i.now, dayStartMs(addDays(d, 1), i.zone));
  const naps = [...i.nights.values()].filter((n) => n.day === d).flatMap((n) => n.segments).filter((s) => s.start >= wake).map((s) => [s.start, s.end] as [number, number]);
  const slots = energySlots(Math.max(wake, dayStart), end, i.heartRate, i.steps, i.workouts, naps);
  const hrvSub = readiness.components.find((c) => c.name === 'HRV')?.score;
  const energy = energyScore(d, sleep.value === undefined ? undefined : sleep, hrvSub, slots, prof);
  return { sleep, readiness, strain, energy };
}

export const scoreLabel = (r: ScoreResult) => {
  if (r.value === undefined) return 'Not enough data';
  const v = r.value;
  if (r.kind === 'strain') return v < 8 ? 'Light' : v < 14 ? 'Moderate' : v < 18 ? 'High' : 'All out';
  return v < 34 ? 'Low' : v < 67 ? 'Fair' : v < 85 ? 'Good' : 'Excellent';
};
