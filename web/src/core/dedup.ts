// Mirror of PulseCore Dedup (cumulative sweep, sleep merge, workout merge, discrete selection).
import type { Sample, SourceRef } from './model';
import { isAsleep, sourceKey, SleepStage, WORKOUT_KEYS } from './model';
import { SourcePriority, lexLess } from './source';
import { type DayKey, type Zone, dayKeyOf, dayStartMs, addDays } from './daykey';

export interface Segment { start: number; end: number; value: number; source: SourceRef; isManual: boolean; isEstimated: boolean }

const INSTANT_MS = 1000;

export function dedupeCumulative(samples: Sample[], priority: SourcePriority): Segment[] {
  if (!samples.length) return [];
  const items = samples.map((s) => {
    let en = s.end;
    if (en <= s.start) en = s.start + INSTANT_MS;
    return { s: s.start, e: en, rate: s.value / (en - s.start), rank: priority.rank(s.source, s.device), key: sourceKey(s.source), sample: s };
  });
  const bounds = [...new Set(items.flatMap((i) => [i.s, i.e]))].sort((a, b) => a - b);
  const byStart = [...items].sort((a, b) => a.s - b.s);
  const out: Segment[] = [];
  let active: typeof items = [];
  let next = 0;
  for (let bi = 0; bi < bounds.length - 1; bi++) {
    const a = bounds[bi], b = bounds[bi + 1];
    active = active.filter((x) => x.e > a);
    while (next < byStart.length && byStart[next].s <= a) {
      if (byStart[next].e > a) active.push(byStart[next]);
      next++;
    }
    if (!active.length) continue;
    let best = active[0];
    for (const it of active.slice(1)) if (lexLess([it.rank, it.key], [best.rank, best.key])) best = it;
    const winners = active.filter((x) => x.key === best.key);
    const amount = winners.reduce((t, x) => t + x.rate * (b - a), 0);
    const manual = winners.every((x) => x.sample.isManual);
    const est = winners.some((x) => x.sample.isEstimated);
    const last = out[out.length - 1];
    if (last && last.end === a && sourceKey(last.source) === sourceKey(best.sample.source) && last.source.name === best.sample.source.name
      && last.isManual === manual && last.isEstimated === est) {
      last.end = b;
      last.value += amount;
    } else {
      out.push({ start: a, end: b, value: amount, source: best.sample.source, isManual: manual, isEstimated: est });
    }
  }
  return out;
}

export const totalCumulative = (s: Sample[], p: SourcePriority) => dedupeCumulative(s, p).reduce((t, x) => t + x.value, 0);

/** Prorates segments into local-day bins. */
export function binByDay(segs: Segment[], z: Zone, filter: (s: Segment) => boolean = () => true): Map<DayKey, number> {
  const out = new Map<DayKey, number>();
  for (const seg of segs) {
    if (!filter(seg)) continue;
    const total = seg.end - seg.start;
    if (total <= 0) { const k = dayKeyOf(seg.start, z); out.set(k, (out.get(k) ?? 0) + seg.value); continue; }
    let cursor = seg.start;
    while (cursor < seg.end) {
      const k = dayKeyOf(cursor, z);
      const be = Math.min(dayStartMs(addDays(k, 1), z), seg.end);
      out.set(k, (out.get(k) ?? 0) + ((be - cursor) / total) * seg.value);
      if (be <= cursor) break;
      cursor = be;
    }
  }
  return out;
}

export const dailyTotals = (s: Sample[], p: SourcePriority, z: Zone) => binByDay(dedupeCumulative(s, p), z);

// ── Sleep ───────────────────────────────────────────────────────────────

export interface SleepNight {
  day: DayKey; start: number; end: number; inBedMinutes: number; asleepMinutes: number; awakeMinutes: number;
  stageMinutes: Record<number, number>; hasStages: boolean; primarySource: SourceRef; sources: string[];
  segments: Segment[]; isEstimated: boolean;
}

export const nightEfficiency = (n: SleepNight) => (n.inBedMinutes > 0 ? Math.min(1, n.asleepMinutes / n.inBedMinutes) : undefined);
export const sleepOnset = (n: SleepNight) => n.segments.find((s) => isAsleep(s.value))?.start ?? n.start;
export function wakeTime(n: SleepNight) {
  for (let i = n.segments.length - 1; i >= 0; i--) if (isAsleep(n.segments[i].value)) return n.segments[i].end;
  return n.end;
}

const specificity = (code: number) => (code === 4 || code === 3 || code === 5 || code === 2 ? 0 : code === 1 ? 1 : 2);

export function sweepSegments(samples: Sample[], priority: SourcePriority): Segment[] {
  if (!samples.length) return [];
  const items = samples.map((x) => ({ s: x.start, e: x.end, rank: priority.rank(x.source, x.device), key: sourceKey(x.source), spec: specificity(Math.trunc(x.value)), sample: x }))
    .sort((a, b) => a.s - b.s);
  const bounds = [...new Set(items.flatMap((i) => [i.s, i.e]))].sort((a, b) => a - b);
  const out: Segment[] = [];
  let active: typeof items = [];
  let next = 0;
  for (let bi = 0; bi < bounds.length - 1; bi++) {
    const a = bounds[bi], b = bounds[bi + 1];
    active = active.filter((x) => x.e > a);
    while (next < items.length && items[next].s <= a) {
      if (items[next].e > a) active.push(items[next]);
      next++;
    }
    if (!active.length) continue;
    let best = active[0];
    for (const it of active.slice(1)) if (lexLess([it.rank, it.key, it.spec], [best.rank, best.key, best.spec])) best = it;
    const last = out[out.length - 1];
    if (last && last.end === a && last.value === best.sample.value && sourceKey(last.source) === sourceKey(best.sample.source) && last.source.name === best.sample.source.name) {
      last.end = b;
    } else {
      out.push({ start: a, end: b, value: best.sample.value, source: best.sample.source, isManual: best.sample.isManual, isEstimated: best.sample.isEstimated });
    }
  }
  return out;
}

const SESSION_GAP = 2 * 3600_000;

function unionMinutes(segs: Segment[]): number {
  const s = [...segs].sort((a, b) => a.start - b.start);
  let total = 0, cs: number | undefined, ce: number | undefined;
  for (const x of s) {
    if (ce !== undefined && x.start <= ce) ce = Math.max(ce, x.end);
    else { if (cs !== undefined && ce !== undefined) total += ce - cs; cs = x.start; ce = x.end; }
  }
  if (cs !== undefined && ce !== undefined) total += ce - cs;
  return total / 60_000;
}

export function sleepNights(samples: Sample[], priority: SourcePriority, z: Zone): SleepNight[] {
  const sleep = samples.filter((s) => s.type === 'sleep' && s.end > s.start);
  const stages = sweepSegments(sleep.filter((s) => Math.trunc(s.value) !== SleepStage.inBed), priority);
  const inBed = sweepSegments(sleep.filter((s) => Math.trunc(s.value) === SleepStage.inBed), priority);
  const all = [...stages.map((s) => [s, false] as const), ...inBed.map((s) => [s, true] as const)].sort((a, b) => a[0].start - b[0].start);
  const sessions: (readonly [Segment, boolean])[][] = [];
  let ce: number | undefined;
  for (const item of all) {
    if (ce !== undefined && item[0].start - ce <= SESSION_GAP) { sessions[sessions.length - 1].push(item); ce = Math.max(ce, item[0].end); }
    else { sessions.push([item]); ce = item[0].end; }
  }
  const byDay = new Map<DayKey, SleepNight>();
  for (const session of sessions) {
    const st = session.filter((x) => !x[1]).map((x) => x[0]);
    const bed = session.filter((x) => x[1]).map((x) => x[0]);
    const stageMinutes: Record<number, number> = {};
    for (const s of st) stageMinutes[s.value] = (stageMinutes[s.value] ?? 0) + (s.end - s.start) / 60_000;
    const asleep = Object.entries(stageMinutes).filter(([k]) => isAsleep(+k)).reduce((t, [, v]) => t + v, 0);
    const awake = stageMinutes[SleepStage.awake] ?? 0;
    const inBedMin = unionMinutes(session.map((x) => x[0]));
    const start = Math.min(...session.map((x) => x[0].start));
    const end = Math.max(...session.map((x) => x[0].end));
    const bySource = new Map<string, { src: SourceRef; v: number }>();
    const add = (s: Segment) => {
      const k = `${s.source.bundleId}|${s.source.name}`;
      const e = bySource.get(k) ?? { src: s.source, v: 0 };
      e.v += s.end - s.start;
      bySource.set(k, e);
    };
    st.filter((s) => isAsleep(s.value)).forEach(add);
    if (!bySource.size) bed.forEach(add);
    let primary: { src: SourceRef; v: number } | undefined;
    for (const e of bySource.values()) {
      if (!primary || e.v > primary.v || (e.v === primary.v && sourceKey(e.src) < sourceKey(primary.src))) primary = e;
    }
    const prim = primary!.src;
    const hasStages = st.some((s) => sourceKey(s.source) === sourceKey(prim) && s.source.name === prim.name && [3, 4, 5].includes(s.value));
    const day = dayKeyOf(end, z);
    const night: SleepNight = { day, start, end, inBedMinutes: inBedMin, asleepMinutes: asleep, awakeMinutes: awake, stageMinutes, hasStages,
      primarySource: prim, sources: [...new Set(session.map((x) => sourceKey(x[0].source)))].sort(), segments: st, isEstimated: st.some((s) => s.isEstimated) };
    const existing = byDay.get(day);
    if (!existing) { byDay.set(day, night); continue; }
    const main = existing.asleepMinutes >= night.asleepMinutes ? existing : night;
    const other = main === existing ? night : existing;
    const split = Math.abs(other.end - main.start) < 4 * 3600_000 || Math.abs(main.end - other.start) < 4 * 3600_000;
    if (split) {
      const merged: SleepNight = { ...main, start: Math.min(main.start, other.start), end: Math.max(main.end, other.end),
        asleepMinutes: main.asleepMinutes + other.asleepMinutes, awakeMinutes: main.awakeMinutes + other.awakeMinutes,
        inBedMinutes: main.inBedMinutes + other.inBedMinutes, stageMinutes: { ...main.stageMinutes },
        segments: [...main.segments, ...other.segments].sort((a, b) => a.start - b.start), sources: [...new Set([...main.sources, ...other.sources])].sort() };
      for (const [k, v] of Object.entries(other.stageMinutes)) merged.stageMinutes[+k] = (merged.stageMinutes[+k] ?? 0) + v;
      byDay.set(day, merged);
    } else byDay.set(day, main);
  }
  return [...byDay.values()].sort((a, b) => (a.day < b.day ? -1 : a.day > b.day ? 1 : 0));
}

// ── Workouts ────────────────────────────────────────────────────────────

const dur = (s: Sample) => s.end - s.start;
export function isDuplicateWorkout(a: Sample, b: Sample) {
  const overlap = Math.min(a.end, b.end) - Math.max(a.start, b.start);
  if (overlap <= 0) return false;
  const shorter = Math.min(dur(a), dur(b));
  return shorter > 0 && overlap / shorter >= 0.5;
}

export function mergeWorkouts(workouts: Sample[], priority: SourcePriority): Sample[] {
  const sorted = workouts.filter((w) => w.type === 'workout').sort((a, b) => a.start - b.start);
  const clusters: Sample[][] = [];
  for (const w of sorted) {
    let idx = -1;
    for (let i = clusters.length - 1; i >= 0; i--) if (clusters[i].some((x) => isDuplicateWorkout(x, w))) { idx = i; break; }
    if (idx >= 0) clusters[idx].push(w); else clusters.push([w]);
  }
  return clusters.map((c) => {
    if (c.length === 1) return c[0];
    const ranked = [...c].sort((a, b) => (priority.isHigher(a.source, a.device, b.source, b.device) ? -1 : 1));
    const keep: Sample = { ...ranked[0], metadata: { ...(ranked[0].metadata ?? {}) } };
    for (const o of ranked.slice(1)) {
      for (const k of [WORKOUT_KEYS.energy, WORKOUT_KEYS.distance, WORKOUT_KEYS.avgHR, WORKOUT_KEYS.hasRoute]) {
        if (keep.metadata![k] === undefined && o.metadata?.[k] !== undefined) keep.metadata![k] = o.metadata[k];
      }
    }
    keep.metadata![WORKOUT_KEYS.mergedFrom] = ranked.slice(1).map((x) => x.id).join(',');
    keep.isManual = c.every((x) => x.isManual);
    return keep;
  });
}

// ── Discrete ────────────────────────────────────────────────────────────

export function selectDiscrete(samples: Sample[], preferred: string | undefined, priority: SourcePriority): Sample[] {
  if (!samples.length) return [];
  if (preferred) {
    const p = samples.filter((s) => sourceKey(s.source) === preferred || s.source.name === preferred);
    if (p.length) return p;
  }
  const counts = new Map<string, { n: number; s: Sample }>();
  for (const s of samples) {
    const k = sourceKey(s.source);
    const e = counts.get(k);
    counts.set(k, { n: (e?.n ?? 0) + 1, s: e?.s ?? s });
  }
  let best: [string, { n: number; s: Sample }] | undefined;
  for (const e of counts) {
    if (!best) { best = e; continue; }
    if (e[1].n > best[1].n || (e[1].n === best[1].n && priority.isHigher(e[1].s.source, e[1].s.device, best[1].s.source, best[1].s.device))) best = e;
  }
  return samples.filter((s) => sourceKey(s.source) === best![0]);
}
