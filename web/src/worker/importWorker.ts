/// <reference lib="webworker" />
// Runs the whole import off the main thread: ZIP → inflate → SAX → IndexedDB.
import { ecgDays, entryStream, findExportXML, listEntries } from './zip';
import { HealthImporter } from './importer';
import { IDBSink, aggKey, clearHealthData, putBatch, setMeta } from '../db/db';
import { SourcePriority } from '../core/source';
import { LOCAL } from '../core/daykey';
import type { FromWorker, ToWorker } from './protocol';
import type { ImportInfo } from '../db/queries';

declare const self: DedicatedWorkerGlobalScope;
let abort: AbortController | undefined;
const post = (m: FromWorker) => self.postMessage(m);

self.onmessage = async (e: MessageEvent<ToWorker>) => {
  const msg = e.data;
  if (msg.kind === 'cancel') { abort?.abort(); return; }
  abort = new AbortController();
  try {
    const file = msg.file;
    let stream: ReadableStream<Uint8Array>;
    let total = file.size;
    let ecg: Record<string, number> = {};
    if (file.name.toLowerCase().endsWith('.xml')) {
      stream = file.stream() as ReadableStream<Uint8Array>;
    } else {
      const entries = await listEntries(file);
      const main = findExportXML(entries);
      if (!main) throw new Error('No export.xml found in this ZIP. Choose the export.zip from Health → profile → Export All Health Data.');
      ecg = Object.fromEntries(ecgDays(entries));
      total = main.uncompressedSize || main.compressedSize;
      stream = await entryStream(file, main);
    }
    await clearHealthData();
    const imp = new HealthImporter(new IDBSink(), LOCAL, new SourcePriority(msg.priority), msg.preferred);
    await imp.parse(stream, total, (progress) => post({ kind: 'progress', progress }), abort.signal);
    const r = await imp.finish((progress) => post({ kind: 'progress', progress }));
    post({ kind: 'progress', progress: { phase: 'aggregating', bytes: 0, totalBytes: 0, records: r.counts.records, detail: 'Saving' } });
    await putBatch('aggregates', r.aggregates.map((a) => ({ ...a, key: aggKey(a) })));
    await putBatch('intraday', r.intraday);
    await putBatch('rings', r.rings);
    for (const [day, n] of Object.entries(ecg)) {
      await putBatch('aggregates', [{ key: `ecg|day|${day}|-1`, metric: 'ecg', period: 'day', day, sum: n, count: n, sourcePolicy: 'merged', isEstimated: false }]);
    }
    const info: ImportInfo = {
      exportDate: r.exportDate, importedAt: Date.now(), fileName: file.name, firstDay: r.firstDay, lastDay: r.lastDay, counts: r.counts,
      me: r.me, sources: r.sources, ecgDays: ecg, timeZone: Intl.DateTimeFormat().resolvedOptions().timeZone,
    };
    await setMeta('import', info);
    post({ kind: 'done', info });
  } catch (err) {
    const m = err instanceof DOMException && err.name === 'AbortError' ? 'Import cancelled.' : (err as Error).message;
    post({ kind: 'error', message: m });
  }
};
