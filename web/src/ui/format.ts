import type { MetricType } from '../core/model';
import { UNIT_SYMBOL } from '../core/units';
import { type DayKey, keyToEpochDay } from '../core/daykey';

const nf = (d = 0) => new Intl.NumberFormat(undefined, { maximumFractionDigits: d });
export const imperial = () => typeof navigator !== 'undefined' && /^en-US/.test(navigator.language);

export function duration(min: number): string {
  const t = Math.round(min), h = Math.floor(t / 60), m = t % 60;
  return h === 0 ? `${m}m` : m === 0 ? `${h}h` : `${h}h ${m}m`;
}

export function fmtValue(v: number | undefined, m: MetricType): string {
  if (v === undefined || !Number.isFinite(v)) return '—';
  switch (m.unit) {
    case 'count': return nf(0).format(v);
    case 'm': return imperial() ? `${nf(2).format(v / 1609.344)} mi` : v >= 1000 ? `${nf(2).format(v / 1000)} km` : `${nf(0).format(v)} m`;
    case 'kg': return imperial() ? `${nf(1).format(v / 0.45359237)} lb` : `${nf(1).format(v)} kg`;
    case 'cm': return `${nf(0).format(v)} cm`;
    case 'degC': return imperial() ? `${nf(1).format(v * 9 / 5 + 32)} °F` : `${nf(1).format(v)} °C`;
    case 'mL': return imperial() ? `${nf(0).format(v / 29.5735)} fl oz` : `${nf(0).format(v)} mL`;
    case 'kcal': return `${nf(0).format(v)} kcal`;
    case 'stage': return duration(v);
    case 'min': return v >= 120 ? duration(v) : `${nf(0).format(v)} min`;
    case 'event': return m.dailyStatistic === 'durationMinutes' ? duration(v) : nf(0).format(v);
    case '%': return `${nf(1).format(v)}%`;
    default: {
      const d = ['ms', 'count/min', 'mmHg'].includes(m.unit) ? 0 : 1;
      return `${nf(d).format(v)} ${UNIT_SYMBOL[m.unit] ?? ''}`.trim();
    }
  }
}

export function fmtDay(k: DayKey, opts: Intl.DateTimeFormatOptions = { weekday: 'short', month: 'short', day: 'numeric' }) {
  return new Date(keyToEpochDay(k) * 86_400_000).toLocaleDateString(undefined, { ...opts, timeZone: 'UTC' });
}

export const SECTION_COLOR: Record<string, string> = { activity: 'var(--activity)', sleep: 'var(--sleep)', heart: 'var(--heart)', body: 'var(--body)' };
export const PALETTE = ['#0072B2', '#E69F00', '#009E73', '#D55E00', '#56B4E9', '#CC79A7', '#F0E442'];
export const STAGE_COLOR: Record<number, string> = { 2: '#E69F00', 5: '#56B4E9', 3: '#0072B2', 4: '#1a2e73', 1: '#4d8fc4', 0: '#999' };
export const scoreColor = (v: number) => (v < 34 ? 'var(--vermillion)' : v < 67 ? 'var(--orange)' : 'var(--green)');
