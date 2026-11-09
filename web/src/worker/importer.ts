// Streaming Apple Health export.xml importer with bounded memory.
//
// - Low-volume types (sleep, workouts, HRV, RHR, body, nutrition, vitals…) are
//   normalized and flushed to the sample sink in batches (IndexedDB in the app).
// - High-volume types (steps, energy, distance, HR, audio, running metrics)
//   are NEVER kept raw: they stream into small per-(type, source, hour)
//   accumulators and per-day intraday arrays (recent window only), so memory
//   is independent of file size. Same policy as iOS (docs/schema.md).
import { SaxesParser, type SaxesTagPlain } from 'saxes';
import { Normalizer, parseDevice, parseHealthDate, type RawSample } from '../core/normalize';
import type { DailyAggregate, DeviceRef, MetricType, Sample, SourceRef } from '../core/model';
import { METRICS, attribution, metric, metricForHK, sourceKey } from '../core/model';
import { SourcePriority } from '../core/source';
import { daily, rollup } from '../core/aggregate';
import { type Zone, addDays, dayKeyOf, epochDayToKey, keyToEpochDay, localHour, localMinuteOfDay } from '../core/daykey';

export interface SampleSink {
  put(samples: Sample[]): Promise<void>;
  /** All stored samples of a type (low-volume types only). */
  all(type: string): Promise<Sample[]>;
}

export interface Rings { day: string; move: number; moveGoal: number; exercise: number; exerciseGoal: number; stand: number; standGoal: number }
export interface IntradayDay { day: string; hr: (number | null)[]; steps: number[] }
export interface ImportResult {
  aggregates: DailyAggregate[];
  intraday: IntradayDay[];
  rings: Rings[];
  sources: Record<string, SourceRef[]>;
  me: { dateOfBirth?: string; biologicalSex?: string };
  exportDate?: number;
  firstDay?: string;
  lastDay?: string;
  counts: { records: number; stored: number; skipped: number; workouts: number };
}

export interface Progress { phase: 'parsing' | 'aggregating' | 'done'; bytes: number; totalBytes: number; records: number; detail?: string }

const HOUR = 3_600_000;
export const INTRADAY_DAYS = 120;

interface HourAcc { v: Float64Array; cov: Float32Array }
interface CumAcc { source: SourceRef; device?: DeviceRef; days: Map<number, HourAcc> } // key: UTC epoch day
interface DiscDay { sum: number; n: number; min: number; max: number; lt: number; lv: number; hours: Float64Array; hn: Uint16Array }
interface DiscAcc { source: SourceRef; device?: DeviceRef; days: Map<string, DiscDay> }

export class HealthImporter {
  private normalizer = new Normalizer();
  private pending: Sample[] = [];
  private cum = new Map<string, CumAcc>();     // `${type}\u0000${attribution}`
  private disc = new Map<string, DiscAcc>();
  private hrMinute = new Map<string, { s: Float32Array; n: Uint16Array }>();
  private steps15 = new Map<string, Map<string, Float32Array>>(); // day → source attr → 96 buckets
  private rings: Rings[] = [];
  private sources = new Map<string, Map<string, SourceRef>>();
  private me: ImportResult['me'] = {};
  private exportDate?: number;
  private intradayFromDay = -Infinity;
  private minDay = Infinity;
  private maxDay = -Infinity;
  counts = { records: 0, stored: 0, skipped: 0, workouts: 0 };

  constructor(private sink: SampleSink, private zone: Zone, private priority = new SourcePriority(), private preferred: Record<string, string> = {}) {}

  // ── Parsing ────────────────────────────────────────────────────────────

  async parse(stream: ReadableStream<Uint8Array>, totalBytes: number, onProgress?: (p: Progress) => void, signal?: AbortSignal): Promise<void> {
    const parser = new SaxesParser({ xmlns: false, position: false });
    const stack: { name: string; attrs: Record<string, string>; meta?: Record<string, string>; stats?: Record<string, string>[]; route?: boolean }[] = [];
    let error: Error | undefined;
    const flushes: Promise<void>[] = [];

    parser.on('opentag', (tag: SaxesTagPlain) => {
      const attrs = tag.attributes as Record<string, string>;
      switch (tag.name) {
        case 'ExportDate': this.exportDate = parseHealthDate(attrs.value); this.updateIntradayWindow(); break;
        case 'Me':
          this.me = { dateOfBirth: attrs.HKCharacteristicTypeIdentifierDateOfBirth || undefined, biologicalSex: attrs.HKCharacteristicTypeIdentifierBiologicalSex || undefined };
          break;
        case 'Record': case 'Workout': case 'Correlation':
          stack.push({ name: tag.name, attrs, meta: {}, stats: [] });
          break;
        case 'MetadataEntry': {
          const top = stack[stack.length - 1];
          if (top?.meta && attrs.key) top.meta[attrs.key] = attrs.value ?? '';
          break;
        }
        case 'WorkoutStatistics': stack[stack.length - 1]?.stats?.push(attrs); break;
        case 'WorkoutRoute': { const top = stack[stack.length - 1]; if (top) top.route = true; break; }
        case 'ActivitySummary': this.addRings(attrs); break;
      }
    });
    parser.on('closetag', (tag: SaxesTagPlain) => {
      if (tag.name !== 'Record' && tag.name !== 'Workout' && tag.name !== 'Correlation') return;
      const item = stack.pop();
      if (!item) return;
      if (item.name === 'Record') this.addRecord(item.attrs, item.meta ?? {});
      else if (item.name === 'Workout') this.addWorkout(item.attrs, item.meta ?? {}, item.stats ?? [], !!item.route);
      if (this.pending.length >= 5000) flushes.push(this.flush());
    });
    parser.on('error', (e: Error) => { error = e; });

    const reader = stream.getReader();
    const decoder = new TextDecoder();
    let bytes = 0, lastReport = 0;
    for (;;) {
      if (signal?.aborted) throw new DOMException('Import cancelled', 'AbortError');
      const { value, done } = await reader.read();
      if (done) break;
      bytes += value.byteLength;
      parser.write(decoder.decode(value, { stream: true }));
      if (error) throw error;
      if (flushes.length) { await Promise.all(flushes.splice(0)); }
      if (bytes - lastReport > 4 * 1024 * 1024) {
        lastReport = bytes;
        onProgress?.({ phase: 'parsing', bytes, totalBytes, records: this.counts.records });
      }
    }
    parser.write(decoder.decode());
    parser.close();
    if (error) throw error;
    await this.flush();
    onProgress?.({ phase: 'parsing', bytes: totalBytes, totalBytes, records: this.counts.records });
  }

  /** Byte counter for progress on compressed input. */
  static counting(stream: ReadableStream<Uint8Array>, onBytes: (n: number) => void): ReadableStream<Uint8Array> {
    let n = 0;
    return stream.pipeThrough(new TransformStream<Uint8Array, Uint8Array>({ transform(chunk, c) { n += chunk.byteLength; onBytes(n); c.enqueue(chunk); } }));
  }

  private updateIntradayWindow() {
    const ref = this.exportDate ?? Date.now();
    this.intradayFromDay = keyToEpochDay(dayKeyOf(ref, this.zone)) - INTRADAY_DAYS;
  }

  private noteSource(type: string, s: SourceRef) {
    const m = this.sources.get(type) ?? this.sources.set(type, new Map()).get(type)!;
    if (!m.has(attribution(s))) m.set(attribution(s), s);
  }

  private addRecord(a: Record<string, string>, meta: Record<string, string>) {
    this.counts.records++;
    const m = metricForHK(a.type);
    if (!m) { this.counts.skipped++; return; }
    const start = parseHealthDate(a.startDate), end = parseHealthDate(a.endDate);
    if (start === undefined || end === undefined) { this.counts.skipped++; return; }
    const num = a.value !== undefined && a.value !== '' ? Number(a.value) : undefined;
    const raw: RawSample = {
      typeIdentifier: a.type, value: num !== undefined && !Number.isNaN(num) ? num : undefined,
      stringValue: num === undefined || Number.isNaN(num) ? a.value : undefined, unit: a.unit, start, end,
      sourceName: a.sourceName ?? '', sourceBundleId: '', device: parseDevice(a.device), metadata: meta,
    };
    // export.xml has no bundle ids; the source name is the key.
    const r = this.normalizer.normalize(raw);
    if (!r.sample) { this.counts.skipped++; return; }
    const s = r.sample;
    this.noteSource(m.id, s.source);
    const d = keyToEpochDay(dayKeyOf(s.start, this.zone));
    if (d < this.minDay) this.minDay = d;
    if (d > this.maxDay) this.maxDay = d;
    if (m.isHighVolume) this.addHighVolume(m, s);
    else this.pending.push(s);
    if (m.id === 'steps') this.addSteps15(s);
  }

  private addWorkout(a: Record<string, string>, meta: Record<string, string>, stats: Record<string, string>[], route: boolean) {
    this.counts.records++;
    const start = parseHealthDate(a.startDate), end = parseHealthDate(a.endDate);
    if (start === undefined || end === undefined) return;
    const num = (v?: string) => (v !== undefined && v !== '' && !Number.isNaN(Number(v)) ? Number(v) : undefined);
    const stat = (type: string, field: string) => {
      const st = stats.find((x) => x.type === type);
      const v = num(st?.[field]);
      return v === undefined ? undefined : { v, unit: st!.unit };
    };
    let energy = num(a.totalEnergyBurned);
    if (energy !== undefined && a.totalEnergyBurnedUnit === 'kJ') energy /= 4.184;
    if (energy === undefined) {
      const e = stat('HKQuantityTypeIdentifierActiveEnergyBurned', 'sum');
      if (e) energy = e.unit === 'kJ' ? e.v / 4.184 : e.v;
    }
    const conv: Record<string, number> = { km: 1000, mi: 1609.344, m: 1, yd: 0.9144 };
    let distance = num(a.totalDistance);
    if (distance !== undefined) distance *= conv[a.totalDistanceUnit] ?? 1;
    else for (const t of ['DistanceWalkingRunning', 'DistanceCycling', 'DistanceSwimming', 'DistanceDownhillSnowSports']) {
      const s = stat(`HKQuantityTypeIdentifier${t}`, 'sum');
      if (s) { distance = s.v * (conv[s.unit] ?? 1); break; }
    }
    const hr = stat('HKQuantityTypeIdentifierHeartRate', 'average')?.v;
    let minutes = num(a.duration);
    if (minutes !== undefined && a.durationUnit === 's') minutes /= 60;
    if (minutes !== undefined && a.durationUnit === 'hr') minutes *= 60;
    const w = this.normalizer.normalizeWorkout({ activityType: a.workoutActivityType ?? 'other', start, end, durationMinutes: minutes, energyKcal: energy,
      distanceMeters: distance, averageHeartRate: hr, hasRoute: route, sourceName: a.sourceName ?? '', sourceBundleId: '', device: parseDevice(a.device), metadata: meta });
    this.counts.workouts++;
    this.noteSource('workout', w.source);
    this.pending.push(w);
  }

  private addRings(a: Record<string, string>) {
    if (!a.dateComponents) return;
    const n = (v?: string) => (v ? Number(v) || 0 : 0);
    this.rings.push({ day: a.dateComponents, move: n(a.activeEnergyBurned), moveGoal: n(a.activeEnergyBurnedGoal), exercise: n(a.appleExerciseTime),
      exerciseGoal: n(a.appleExerciseTimeGoal), stand: n(a.appleStandHours), standGoal: n(a.appleStandHoursGoal) });
  }

  private addHighVolume(m: MetricType, s: Sample) {
    const key = `${m.id}\u0000${attribution(s.source)}`;
    if (m.kind === 'cumulative') {
      const acc = this.cum.get(key) ?? this.cum.set(key, { source: s.source, device: s.device, days: new Map() }).get(key)!;
      const end = s.end > s.start ? s.end : s.start + 1000;
      const total = end - s.start;
      let t = s.start;
      while (t < end) {
        const hourStart = Math.floor(t / HOUR) * HOUR;
        const segEnd = Math.min(end, hourStart + HOUR);
        const frac = (segEnd - t) / total;
        const day = Math.floor(hourStart / (24 * HOUR)), h = Math.floor((hourStart % (24 * HOUR)) / HOUR);
        const d = acc.days.get(day) ?? acc.days.set(day, { v: new Float64Array(24), cov: new Float32Array(24) }).get(day)!;
        d.v[h] += s.value * frac;
        d.cov[h] = Math.min(3600, d.cov[h] + (segEnd - t) / 1000);
        t = segEnd;
      }
    } else {
      const acc = this.disc.get(key) ?? this.disc.set(key, { source: s.source, device: s.device, days: new Map() }).get(key)!;
      const dk = dayKeyOf(s.start, this.zone);
      const d = acc.days.get(dk) ?? acc.days.set(dk, { sum: 0, n: 0, min: Infinity, max: -Infinity, lt: -Infinity, lv: 0, hours: new Float64Array(24), hn: new Uint16Array(24) }).get(dk)!;
      d.sum += s.value; d.n++;
      if (s.value < d.min) d.min = s.value;
      if (s.value > d.max) d.max = s.value;
      if (s.end > d.lt) { d.lt = s.end; d.lv = s.value; }
      const h = localHour(s.start, this.zone);
      d.hours[h] += s.value; d.hn[h]++;
      if (m.id === 'heartRate' && keyToEpochDay(dk) >= this.intradayFromDay) {
        const arr = this.hrMinute.get(dk) ?? this.hrMinute.set(dk, { s: new Float32Array(1440), n: new Uint16Array(1440) }).get(dk)!;
        const mi = localMinuteOfDay(s.start, this.zone);
        arr.s[mi] += s.value; arr.n[mi]++;
      }
    }
  }

  private addSteps15(s: Sample) {
    const dk = dayKeyOf(s.start, this.zone);
    if (keyToEpochDay(dk) < this.intradayFromDay) return;
    const bySrc = this.steps15.get(dk) ?? this.steps15.set(dk, new Map()).get(dk)!;
    const a = attribution(s.source);
    const arr = bySrc.get(a) ?? bySrc.set(a, new Float32Array(96)).get(a)!;
    arr[Math.min(95, Math.floor(localMinuteOfDay(s.start, this.zone) / 15))] += s.value;
  }

  private async flush() {
    if (!this.pending.length) return;
    const batch = this.pending;
    this.pending = [];
    this.counts.stored += batch.length;
    await this.sink.put(batch);
  }

  // ── Aggregation ────────────────────────────────────────────────────────

  async finish(onProgress?: (p: Progress) => void): Promise<ImportResult> {
    await this.flush();
    if (this.exportDate === undefined) this.updateIntradayWindow();
    const aggregates: DailyAggregate[] = [];
    const types = METRICS.filter((m) => m.healthKitIdentifier);
    for (const m of types) {
      onProgress?.({ phase: 'aggregating', bytes: 0, totalBytes: 0, records: this.counts.records, detail: m.displayName });
      let dailyRows: DailyAggregate[] = [];
      let hourly: DailyAggregate[] = [];
      if (m.isHighVolume && m.kind === 'cumulative') [dailyRows, hourly] = this.cumulativeDaily(m);
      else if (m.isHighVolume) [dailyRows, hourly] = this.discreteDaily(m);
      else {
        const samples = await this.sink.all(m.id);
        if (!samples.length) continue;
        dailyRows = daily(m, samples, { priority: this.priority, preferredSource: this.preferred, zone: this.zone });
      }
      if (!dailyRows.length) continue;
      aggregates.push(...dailyRows, ...hourly);
      for (const p of ['week', 'month', 'year'] as const) aggregates.push(...rollup(dailyRows, m, p));
    }
    const intraday: IntradayDay[] = [];
    const days = new Set([...this.hrMinute.keys(), ...this.steps15.keys()]);
    for (const day of days) {
      const hr = this.hrMinute.get(day);
      const steps = this.dedupSteps15(day);
      intraday.push({ day, hr: hr ? Array.from(hr.s, (v, i) => (hr.n[i] ? v / hr.n[i] : null)) : new Array(1440).fill(null), steps });
    }
    const sources: Record<string, SourceRef[]> = {};
    for (const [k, v] of this.sources) sources[k] = [...v.values()];
    onProgress?.({ phase: 'done', bytes: 0, totalBytes: 0, records: this.counts.records });
    return {
      aggregates, intraday, rings: this.rings, sources, me: this.me, exportDate: this.exportDate,
      firstDay: Number.isFinite(this.minDay) ? epochDayToKey(this.minDay) : undefined,
      lastDay: Number.isFinite(this.maxDay) ? epochDayToKey(this.maxDay) : undefined, counts: this.counts,
    };
  }

  /** Hour-level priority dedup: higher-priority sources claim their covered
   *  share of each hour first; lower-priority sources fill only the rest. */
  private cumulativeDaily(m: MetricType): [DailyAggregate[], DailyAggregate[]] {
    const accs = [...this.cum.entries()].filter(([k]) => k.startsWith(m.id + '\u0000')).map(([, v]) => v);
    if (!accs.length) return [[], []];
    const p = this.priority.preferring(this.preferred[m.id]);
    accs.sort((a, b) => (p.isHigher(a.source, a.device, b.source, b.device) ? -1 : 1));
    const allDays = new Set<number>();
    for (const a of accs) for (const d of a.days.keys()) allDays.add(d);
    const dayTotals = new Map<string, { sum: number; src: Map<string, number> }>();
    const hourRows = new Map<string, number>();
    for (const utcDay of allDays) {
      for (let h = 0; h < 24; h++) {
        let remaining = 3600, total = 0;
        const contrib: [string, number][] = [];
        for (const a of accs) {
          const d = a.days.get(utcDay);
          if (!d || (d.v[h] === 0 && d.cov[h] === 0)) continue;
          const cov = Math.max(1, d.cov[h]);
          const take = Math.min(cov, remaining);
          const v = d.v[h] * (take / cov);
          total += v;
          remaining -= take;
          contrib.push([attribution(a.source), v]);
          if (remaining <= 0) break;
        }
        if (!contrib.length) continue;
        const hourStart = (utcDay * 24 + h) * HOUR;
        const dk = dayKeyOf(hourStart, this.zone);
        const e = dayTotals.get(dk) ?? dayTotals.set(dk, { sum: 0, src: new Map() }).get(dk)!;
        e.sum += total;
        for (const [k, v] of contrib) e.src.set(k, (e.src.get(k) ?? 0) + v);
        if (keyToEpochDay(dk) >= this.intradayFromDay) {
          const hk = `${dk}|${localHour(hourStart, this.zone)}`;
          hourRows.set(hk, (hourRows.get(hk) ?? 0) + total);
        }
      }
    }
    const policy = this.preferred[m.id] ? `pref:${this.preferred[m.id]}` : 'merged';
    const dailyRows = [...dayTotals].map(([day, e]) => {
      let primary: string | undefined, best = -1;
      for (const [k, v] of e.src) if (v > best) { best = v; primary = k; }
      return { metric: m.id, period: 'day' as const, day, sum: e.sum, count: 1, primarySource: primary, sourcePolicy: policy, isEstimated: false };
    }).sort((a, b) => (a.day < b.day ? -1 : 1));
    const hourly = [...hourRows].map(([k, sum]) => {
      const [day, hour] = k.split('|');
      return { metric: m.id, period: 'hour' as const, day, hour: Number(hour), sum, count: 1, sourcePolicy: policy, isEstimated: false };
    });
    return [dailyRows, hourly];
  }

  /** One source per day (preferred, else most readings) — like DiscreteSourceSelector. */
  private discreteDaily(m: MetricType): [DailyAggregate[], DailyAggregate[]] {
    const accs = [...this.disc.entries()].filter(([k]) => k.startsWith(m.id + '\u0000')).map(([, v]) => v);
    const days = new Set<string>();
    for (const a of accs) for (const d of a.days.keys()) days.add(d);
    const p = this.priority.preferring(this.preferred[m.id]);
    const policy = this.preferred[m.id] ? `pref:${this.preferred[m.id]}` : 'merged';
    const out: DailyAggregate[] = [], hourly: DailyAggregate[] = [];
    for (const day of days) {
      // Same rule as DiscreteSourceSelector: preferred if present, else most
      // readings, ties broken by source priority.
      const present = accs.filter((a) => a.days.has(day));
      const pref = this.preferred[m.id];
      let acc = pref ? present.find((a) => sourceKey(a.source) === pref || a.source.name === pref) : undefined;
      if (!acc) {
        for (const a of present) {
          if (!acc) { acc = a; continue; }
          const na = a.days.get(day)!.n, nb = acc.days.get(day)!.n;
          if (na > nb || (na === nb && p.isHigher(a.source, a.device, acc.source, acc.device))) acc = a;
        }
      }
      if (!acc) continue;
      const d = acc.days.get(day)!;
      out.push({ metric: m.id, period: 'day', day, sum: d.sum, average: d.sum / d.n, min: d.min, max: d.max, latest: d.lv, count: d.n,
        primarySource: attribution(acc.source), sourcePolicy: policy, isEstimated: false });
      if (keyToEpochDay(day) >= this.intradayFromDay) {
        for (let h = 0; h < 24; h++) if (d.hn[h]) hourly.push({ metric: m.id, period: 'hour', day, hour: h, average: d.hours[h] / d.hn[h], count: d.hn[h], sourcePolicy: policy, isEstimated: false });
      }
    }
    return [out.sort((a, b) => (a.day < b.day ? -1 : 1)), hourly];
  }

  private dedupSteps15(day: string): number[] {
    const bySrc = this.steps15.get(day);
    const out = new Array(96).fill(0);
    if (!bySrc) return out;
    const p = this.priority.preferring(this.preferred.steps);
    const srcs = [...bySrc.keys()].map((a) => ({ a, ref: { bundleId: a.split('|')[0], name: a.split('|')[1] ?? '' } }))
      .sort((x, y) => (p.isHigher(x.ref, undefined, y.ref, undefined) ? -1 : 1));
    for (let i = 0; i < 96; i++) for (const s of srcs) { const v = bySrc.get(s.a)![i]; if (v > 0) { out[i] = v; break; } }
    return out;
  }
}

export { metric, addDays };
