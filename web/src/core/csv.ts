// Mirror of PulseCore CSVExporter.
import type { DailyAggregate, MetricType, Sample } from './model';
import { aggValue } from './model';
import { UNIT_SYMBOL } from './units';
import { type DayKey, range } from './daykey';

export function escapeCSV(s: string): string {
  return /[",\n\r]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
}

/** Fixed decimals, trailing zeros trimmed ("-0" → "0"). Note: JS toFixed rounds half away from zero. */
export function csvNumber(v: number | undefined, digits = 2): string {
  if (v === undefined || !Number.isFinite(v)) return '';
  let s = v.toFixed(digits);
  if (s.includes('.')) s = s.replace(/0+$/, '').replace(/\.$/, '');
  return s === '-0' ? '0' : s;
}

const line = (f: string[]) => f.map(escapeCSV).join(',');
const unitLabel = (m: MetricType) => (m.unit === 'stage' ? 'min' : m.unit === 'event' ? (m.dailyStatistic === 'durationMinutes' ? 'min' : 'count') : UNIT_SYMBOL[m.unit] ?? m.unit);

export function dailySummaryCSV(metrics: MetricType[], rows: Map<string, DailyAggregate[]>, from: DayKey, to: DayKey): string {
  const header = ['date'];
  const est = new Set<string>();
  for (const m of metrics) {
    const ul = unitLabel(m);
    header.push(ul ? `${m.displayName} (${ul})` : m.displayName);
    if (rows.get(m.id)?.some((r) => r.isEstimated)) { est.add(m.id); header.push(`${m.displayName} estimated`); }
  }
  const out = [line(header)];
  const idx = new Map([...rows].map(([k, v]) => [k, new Map(v.map((r) => [r.day, r]))]));
  for (const d of range(from, to)) {
    const f = [d];
    for (const m of metrics) {
      const r = idx.get(m.id)?.get(d);
      f.push(csvNumber(r ? aggValue(r, m.dailyStatistic) : undefined));
      if (est.has(m.id)) f.push(r?.isEstimated ? 'yes' : '');
    }
    out.push(line(f));
  }
  return out.join('\r\n') + '\r\n';
}

export function samplesCSV(samples: Sample[]): string {
  const isoS = (ms: number) => new Date(ms).toISOString().replace(/\.\d{3}Z$/, 'Z');
  const out = [line(['id', 'type', 'value', 'unit', 'start', 'end', 'source', 'source_bundle_id', 'device', 'is_manual', 'is_estimated', 'metadata'])];
  for (const s of [...samples].sort((a, b) => (a.start - b.start) || (a.id < b.id ? -1 : 1))) {
    const meta = Object.entries(s.metadata ?? {}).sort(([a], [b]) => (a < b ? -1 : 1)).map(([k, v]) => `${k}=${v}`).join(';');
    out.push(line([s.id, s.type, csvNumber(s.value, 4), s.unit, isoS(s.start), isoS(s.end), s.source.name, s.source.bundleId,
      s.device?.name ?? s.device?.model ?? '', String(s.isManual), String(s.isEstimated), meta]));
  }
  return out.join('\r\n') + '\r\n';
}
