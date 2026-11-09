// Read API used by the UI.
import type { DailyAggregate, Sample, SourceRef } from '../core/model';
import { db } from './db';
import type { IntradayDay, Rings } from '../worker/importer';

export interface ImportInfo {
  exportDate?: number;
  importedAt: number;
  fileName: string;
  firstDay?: string;
  lastDay?: string;
  counts: { records: number; stored: number; skipped: number; workouts: number };
  me: { dateOfBirth?: string; biologicalSex?: string };
  sources: Record<string, SourceRef[]>;
  ecgDays: Record<string, number>;
  timeZone: string;
}

export async function aggregates(metric: string, period: DailyAggregate['period'], from: string, to: string): Promise<DailyAggregate[]> {
  const d = await db();
  return d.getAllFromIndex('aggregates', 'metric_period_day', IDBKeyRange.bound([metric, period, from], [metric, period, to]));
}

export async function latestAggregate(metric: string, onOrBefore = '9999-12-31'): Promise<DailyAggregate | undefined> {
  const d = await db();
  const cur = await d.transaction('aggregates').store.index('metric_period_day')
    .openCursor(IDBKeyRange.bound([metric, 'day', ''], [metric, 'day', onOrBefore]), 'prev');
  return cur?.value;
}

export async function earliestDay(metric: string): Promise<string | undefined> {
  const d = await db();
  const cur = await d.transaction('aggregates').store.index('metric_period_day').openCursor(IDBKeyRange.bound([metric, 'day', ''], [metric, 'day', '￿']));
  return cur?.value.day;
}

export async function samples(type: string, from: number, to: number): Promise<Sample[]> {
  const d = await db();
  return d.getAllFromIndex('samples', 'type_start', IDBKeyRange.bound([type, from], [type, to], false, true));
}

export async function intraday(day: string): Promise<IntradayDay | undefined> {
  return (await db()).get('intraday', day);
}

export async function rings(day: string): Promise<Rings | undefined> {
  return (await db()).get('rings', day);
}

export async function hasData(): Promise<boolean> {
  return (await (await db()).count('aggregates')) > 0;
}
