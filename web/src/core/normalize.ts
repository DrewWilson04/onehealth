// Mirror of PulseCore Normalizer / HealthDate / DeviceRef.parseExportDescription.
import { convert } from './units';
import type { DeviceRef, Sample } from './model';
import { metricForHK, sleepStageFromExport, WORKOUT_KEYS } from './model';

export interface RawSample {
  typeIdentifier: string;
  value?: number;
  stringValue?: string;
  unit?: string;
  start: number;
  end: number;
  sourceName: string;
  sourceBundleId: string;
  device?: DeviceRef;
  metadata: Record<string, string>;
  uuid?: string;
}

export type NormalizationIssue = 'unknownType' | 'unknownUnit' | 'missingValue' | 'unknownCategoryValue' | 'invalidInterval';

/** "2024-01-15 07:30:00 -0500" → epoch ms (hand-rolled; identical to iOS). */
export function parseHealthDate(s: string): number | undefined {
  if (s.length < 19) return undefined;
  const n = (from: number, len: number) => {
    let v = 0;
    for (let i = from; i < from + len; i++) {
      const c = s.charCodeAt(i) - 48;
      if (c < 0 || c > 9) return NaN;
      v = v * 10 + c;
    }
    return v;
  };
  const y = n(0, 4), mo = n(5, 2), d = n(8, 2), h = n(11, 2), mi = n(14, 2), se = n(17, 2);
  if ([y, mo, d, h, mi, se].some(Number.isNaN)) return undefined;
  let off = 0;
  if (s.length >= 25) {
    const sign = s[20];
    const oh = n(21, 2), om = n(23, 2);
    if ((sign === '+' || sign === '-') && !Number.isNaN(oh) && !Number.isNaN(om)) off = (oh * 3600 + om * 60) * (sign === '-' ? -1 : 1);
  }
  return (Date.UTC(y, mo - 1, d, h, mi, se) / 1000 - off) * 1000;
}

const DEVICE_KEYS = ['name', 'manufacturer', 'model', 'hardware', 'software', 'localIdentifier', 'UDIDeviceIdentifier', 'firmware'];
export function parseDevice(s: string | undefined): DeviceRef | undefined {
  if (!s) return undefined;
  const positions: { key: string; start: number; valueStart: number }[] = [];
  for (const key of DEVICE_KEYS) {
    let from = 0;
    for (;;) {
      const i = s.indexOf(`${key}:`, from);
      if (i < 0) break;
      if (i === 0 || s[i - 1] === ' ') { positions.push({ key, start: i, valueStart: i + key.length + 1 }); break; }
      from = i + key.length + 1;
    }
  }
  positions.sort((a, b) => a.start - b.start);
  const f: Record<string, string> = {};
  positions.forEach((p, i) => {
    const end = i + 1 < positions.length ? positions[i + 1].start : (s.lastIndexOf('>') >= 0 ? s.lastIndexOf('>') : s.length);
    let v = s.slice(p.valueStart, Math.max(p.valueStart, end)).trim();
    if (v.endsWith(',')) v = v.slice(0, -1);
    f[p.key] = v.trim();
  });
  if (!Object.keys(f).length) return undefined;
  return { name: f.name, model: f.model, manufacturer: f.manufacturer, hardwareVersion: f.hardware };
}

/** FNV-1a 64-bit, hex (BigInt) — identical to Swift. */
export function fnv1a64Hex(s: string): string {
  let h = 0xcbf29ce484222325n;
  const bytes = new TextEncoder().encode(s);
  for (const b of bytes) {
    h ^= BigInt(b);
    h = (h * 0x100000001b3n) & 0xffffffffffffffffn;
  }
  return h.toString(16).padStart(16, '0');
}

/** Swift String(format: "%.6f") equivalent for typical health values. */
const fixed6 = (v: number) => v.toFixed(6);

export function stableId(r: RawSample): string {
  const v = r.value !== undefined ? fixed6(r.value) : (r.stringValue ?? '');
  const key = `${r.typeIdentifier}|${Math.trunc(r.start / 1000)}|${Math.trunc(r.end / 1000)}|${v}|${r.sourceBundleId || r.sourceName}`;
  return 'x' + fnv1a64Hex(key);
}

export function shortActivityName(s: string): string {
  const p = 'HKWorkoutActivityType';
  let n = s.startsWith(p) ? s.slice(p.length) : s;
  if (n) n = n[0].toLowerCase() + n.slice(1);
  return n;
}

export class Normalizer {
  constructor(public ownBundleIdPrefix = '') {}

  normalize(raw: RawSample): { sample?: Sample; issue?: NormalizationIssue } {
    const m = metricForHK(raw.typeIdentifier);
    if (!m) return { issue: 'unknownType' };
    if (raw.end < raw.start) return { issue: 'invalidInterval' };
    let value: number;
    switch (m.kind) {
      case 'cumulative': case 'discrete': {
        if (raw.value === undefined || !Number.isFinite(raw.value)) return { issue: 'missingValue' };
        if (raw.unit === undefined) return { issue: 'unknownUnit' };
        const c = convert(raw.value, raw.unit, m.unit);
        if (c === undefined) return { issue: 'unknownUnit' };
        value = c;
        break;
      }
      case 'category': {
        if (m.id === 'sleep') {
          const st = raw.stringValue !== undefined ? sleepStageFromExport(raw.stringValue)
            : (raw.value !== undefined && raw.value >= 0 && raw.value <= 5 ? Math.trunc(raw.value) : undefined);
          if (st === undefined) return { issue: 'unknownCategoryValue' };
          value = st;
        } else if (raw.value !== undefined) value = raw.value;
        else if (raw.stringValue !== undefined) value = raw.stringValue === 'HKCategoryValueAppleStandHourIdle' ? 1 : 0;
        else value = 0;
        break;
      }
      case 'workout':
        if (raw.value === undefined) return { issue: 'missingValue' };
        value = convert(raw.value, raw.unit ?? 'min', 'min') ?? raw.value;
        break;
      case 'ecg':
        value = raw.value ?? 0;
    }
    const isManual = raw.metadata.HKWasUserEntered === '1' || (!!this.ownBundleIdPrefix && raw.sourceBundleId.startsWith(this.ownBundleIdPrefix));
    const meta = Object.keys(raw.metadata).length ? raw.metadata : undefined;
    return {
      sample: {
        id: raw.uuid ?? stableId(raw), type: m.id, value, unit: m.unit, start: raw.start, end: Math.max(raw.start, raw.end),
        source: { bundleId: raw.sourceBundleId, name: raw.sourceName }, device: raw.device, isManual, isEstimated: false, metadata: meta,
      },
    };
  }

  normalizeWorkout(w: { activityType: string; start: number; end: number; durationMinutes?: number; energyKcal?: number; distanceMeters?: number;
    averageHeartRate?: number; hasRoute: boolean; sourceName: string; sourceBundleId: string; device?: DeviceRef; metadata: Record<string, string>; uuid?: string }): Sample {
    const meta: Record<string, string> = { ...w.metadata, [WORKOUT_KEYS.activityType]: shortActivityName(w.activityType) };
    if (w.energyKcal !== undefined) meta[WORKOUT_KEYS.energy] = w.energyKcal.toFixed(1);
    if (w.distanceMeters !== undefined) meta[WORKOUT_KEYS.distance] = w.distanceMeters.toFixed(1);
    if (w.averageHeartRate !== undefined) meta[WORKOUT_KEYS.avgHR] = w.averageHeartRate.toFixed(1);
    if (w.hasRoute) meta[WORKOUT_KEYS.hasRoute] = '1';
    const minutes = w.durationMinutes ?? (w.end - w.start) / 60_000;
    const raw: RawSample = { typeIdentifier: 'HKWorkoutTypeIdentifier', value: minutes, unit: 'min', start: w.start, end: w.end,
      sourceName: w.sourceName, sourceBundleId: w.sourceBundleId, device: w.device, metadata: meta, uuid: w.uuid };
    const isManual = w.metadata.HKWasUserEntered === '1' || (!!this.ownBundleIdPrefix && w.sourceBundleId.startsWith(this.ownBundleIdPrefix));
    return { id: w.uuid ?? stableId(raw), type: 'workout', value: minutes, unit: 'min', start: w.start, end: w.end,
      source: { bundleId: w.sourceBundleId, name: w.sourceName }, device: w.device, isManual, isEstimated: false, metadata: meta };
  }
}
