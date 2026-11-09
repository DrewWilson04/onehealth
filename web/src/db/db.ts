// IndexedDB storage (via idb). Everything stays in this browser profile;
// nothing is uploaded. Shapes mirror /docs/schema.md.
import { openDB, type DBSchema, type IDBPDatabase } from 'idb';
import type { DailyAggregate, Sample } from '../core/model';
import type { IntradayDay, Rings, SampleSink } from '../worker/importer';

export type StoredAggregate = DailyAggregate & { key: string };

interface PBSchema extends DBSchema {
  samples: { key: string; value: Sample; indexes: { type: string; type_start: [string, number] } };
  aggregates: { key: string; value: StoredAggregate; indexes: { metric_period_day: [string, string, string] } };
  intraday: { key: string; value: IntradayDay };
  rings: { key: string; value: Rings };
  meta: { key: string; value: unknown };
}

export const DB_NAME = 'pulseboard';
let dbp: Promise<IDBPDatabase<PBSchema>> | undefined;

export function db(): Promise<IDBPDatabase<PBSchema>> {
  dbp ??= openDB<PBSchema>(DB_NAME, 1, {
    upgrade(d) {
      const s = d.createObjectStore('samples', { keyPath: 'id' });
      s.createIndex('type', 'type');
      s.createIndex('type_start', ['type', 'start']);
      const a = d.createObjectStore('aggregates', { keyPath: 'key' });
      a.createIndex('metric_period_day', ['metric', 'period', 'day']);
      d.createObjectStore('intraday', { keyPath: 'day' });
      d.createObjectStore('rings', { keyPath: 'day' });
      d.createObjectStore('meta');
    },
  });
  return dbp;
}

export const aggKey = (a: DailyAggregate) => `${a.metric}|${a.period}|${a.day}|${a.hour ?? -1}`;

export class IDBSink implements SampleSink {
  async put(samples: Sample[]) {
    const d = await db();
    const tx = d.transaction('samples', 'readwrite');
    for (const s of samples) tx.store.put(s);
    await tx.done;
  }
  async all(type: string) {
    return (await db()).getAllFromIndex('samples', 'type', type);
  }
}

export async function clearHealthData() {
  const d = await db();
  const tx = d.transaction(['samples', 'aggregates', 'intraday', 'rings'], 'readwrite');
  await Promise.all([tx.objectStore('samples').clear(), tx.objectStore('aggregates').clear(), tx.objectStore('intraday').clear(), tx.objectStore('rings').clear()]);
  await tx.done;
  await d.delete('meta', 'import');
}

export async function deleteEverything() {
  const d = await db();
  d.close();
  dbp = undefined;
  await new Promise<void>((res, rej) => {
    const r = indexedDB.deleteDatabase(DB_NAME);
    r.onsuccess = () => res();
    r.onerror = () => rej(r.error);
    r.onblocked = () => res();
  });
}

export async function putBatch<T>(store: 'aggregates' | 'intraday' | 'rings', rows: T[], batch = 5000) {
  const d = await db();
  for (let i = 0; i < rows.length; i += batch) {
    const tx = d.transaction(store, 'readwrite');
    for (const r of rows.slice(i, i + batch)) tx.store.put(r as never);
    await tx.done;
  }
}

export async function getMeta<T>(key: string): Promise<T | undefined> {
  return (await (await db()).get('meta', key)) as T | undefined;
}
export async function setMeta(key: string, value: unknown) {
  await (await db()).put('meta', value, key);
}
