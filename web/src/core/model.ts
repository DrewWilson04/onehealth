// Platform-neutral schema — mirror of PulseCore Model (see /docs/schema.md).
import registry from '../../../docs/fixtures/metrics_registry.json';

export type MetricUnit = string;
export type MetricKind = 'cumulative' | 'discrete' | 'category' | 'workout' | 'ecg';
export type DailyStatistic = 'sum' | 'average' | 'latest' | 'durationMinutes' | 'count';
export type Section = 'activity' | 'sleep' | 'heart' | 'body';
export type Confidence = 'low' | 'medium' | 'high';

export interface MetricType {
  id: string;
  displayName: string;
  unit: MetricUnit;
  kind: MetricKind;
  dailyStatistic: DailyStatistic;
  section: Section;
  healthKitIdentifier: string | null;
  isHighVolume: boolean;
  isWritable: boolean;
  higherIsBetter: boolean | null;
  symbol: string;
}

/** Imported verbatim from the iOS registry export — parity by construction. */
export const METRICS: MetricType[] = (registry as { metrics: MetricType[] }).metrics;
const byId = new Map(METRICS.map((m) => [m.id, m]));
const byHK = new Map(METRICS.filter((m) => m.healthKitIdentifier).map((m) => [m.healthKitIdentifier!, m]));
export const metric = (id: string) => byId.get(id);
export const metricForHK = (hk: string) => byHK.get(hk);
export const metricsIn = (s: Section) => METRICS.filter((m) => m.section === s);

export const SECTIONS: { id: Section; title: string }[] = [
  { id: 'activity', title: 'Activity & Workouts' },
  { id: 'sleep', title: 'Sleep & Recovery' },
  { id: 'heart', title: 'Heart & Vitals' },
  { id: 'body', title: 'Body & Nutrition' },
];

export interface SourceRef { bundleId: string; name: string }
export interface DeviceRef { name?: string; model?: string; manufacturer?: string; hardwareVersion?: string }

export interface Sample {
  id: string;
  type: string;
  value: number;
  unit: MetricUnit;
  /** epoch ms */
  start: number;
  end: number;
  source: SourceRef;
  device?: DeviceRef;
  isManual: boolean;
  isEstimated: boolean;
  confidence?: Confidence;
  metadata?: Record<string, string>;
}

export const sourceKey = (s: SourceRef) => (s.bundleId ? s.bundleId : s.name);
export const attribution = (s: SourceRef) => (s.name ? `${s.bundleId}|${s.name}` : s.bundleId);
export function parseAttribution(a: string): SourceRef {
  const i = a.indexOf('|');
  return i < 0 ? { bundleId: a, name: '' } : { bundleId: a.slice(0, i), name: a.slice(i + 1) };
}

export enum SleepStage { inBed = 0, asleepUnspecified = 1, awake = 2, core = 3, deep = 4, rem = 5 }
export const isAsleep = (s: number) => s === 1 || s === 3 || s === 4 || s === 5;
export const STAGE_LABEL: Record<number, string> = { 0: 'In Bed', 1: 'Asleep', 2: 'Awake', 3: 'Core', 4: 'Deep', 5: 'REM' };
export function sleepStageFromExport(v: string): SleepStage | undefined {
  switch (v) {
    case 'HKCategoryValueSleepAnalysisInBed': return SleepStage.inBed;
    case 'HKCategoryValueSleepAnalysisAsleep':
    case 'HKCategoryValueSleepAnalysisAsleepUnspecified': return SleepStage.asleepUnspecified;
    case 'HKCategoryValueSleepAnalysisAwake': return SleepStage.awake;
    case 'HKCategoryValueSleepAnalysisAsleepCore': return SleepStage.core;
    case 'HKCategoryValueSleepAnalysisAsleepDeep': return SleepStage.deep;
    case 'HKCategoryValueSleepAnalysisAsleepREM': return SleepStage.rem;
    default: return undefined;
  }
}

export const WORKOUT_KEYS = {
  activityType: 'activityType', energy: 'energyKcal', distance: 'distanceM', avgHR: 'avgHR',
  hasRoute: 'hasRoute', sets: 'PulseBoardSets', mergedFrom: 'mergedFrom',
} as const;

export interface DailyAggregate {
  metric: string;
  period: 'hour' | 'day' | 'week' | 'month' | 'year';
  day: string;
  hour?: number;
  sum?: number;
  average?: number;
  min?: number;
  max?: number;
  latest?: number;
  count: number;
  primarySource?: string;
  sourcePolicy: string;
  isEstimated: boolean;
  confidence?: Confidence;
}

export function aggValue(a: DailyAggregate, stat: DailyStatistic): number | undefined {
  switch (stat) {
    case 'sum': case 'durationMinutes': return a.sum;
    case 'average': return a.average;
    case 'latest': return a.latest ?? a.average;
    case 'count': return a.count;
  }
}
