import { describe, expect, it } from 'vitest';
import { buildZip, streamToText } from './zipBuilder';
import { SAMPLE_EXPORT } from './sampleExport';
import { entryStream, findExportXML, listEntries, ecgDays } from '../zip';
import { HealthImporter, type SampleSink } from '../importer';
import type { Sample } from '../../core/model';
import { UTC } from '../../core/daykey';

class MemorySink implements SampleSink {
  map = new Map<string, Sample>();
  async put(s: Sample[]) { for (const x of s) this.map.set(x.id, x); }
  async all(type: string) { return [...this.map.values()].filter((s) => s.type === type); }
}

const textStream = (s: string, chunk = 777) => new ReadableStream<Uint8Array>({
  start(c) { const b = new TextEncoder().encode(s); for (let i = 0; i < b.length; i += chunk) c.enqueue(b.slice(i, i + chunk)); c.close(); },
});

describe('zip reader', () => {
  for (const zip64 of [false, true]) {
    it(`reads ${zip64 ? 'ZIP64' : 'standard'} archives and streams deflated entries`, async () => {
      const xml = new TextEncoder().encode(SAMPLE_EXPORT);
      const zip = buildZip([
        { name: 'apple_health_export/export.xml', data: xml },
        { name: 'apple_health_export/export_cda.xml', data: new TextEncoder().encode('<cda/>') },
        { name: 'apple_health_export/electrocardiograms/ecg_2024-03-10.csv', data: new TextEncoder().encode('a,b'), store: true },
      ], zip64);
      const blob = new Blob([zip]);
      const entries = await listEntries(blob);
      expect(entries.map((e) => e.name)).toHaveLength(3);
      const main = findExportXML(entries)!;
      expect(main.name).toBe('apple_health_export/export.xml');
      expect(main.uncompressedSize).toBe(xml.length);
      expect(await streamToText(await entryStream(blob, main))).toBe(SAMPLE_EXPORT);
      expect(ecgDays(entries).get('2024-03-10')).toBe(1);
    });
  }
  it('rejects non-zip input', async () => {
    await expect(listEntries(new Blob([new Uint8Array(100)]))).rejects.toThrow(/Not a ZIP/);
  });
});

describe('importer', () => {
  it('parses and aggregates a realistic export', async () => {
    const sink = new MemorySink();
    const imp = new HealthImporter(sink, UTC);
    await imp.parse(textStream(SAMPLE_EXPORT), SAMPLE_EXPORT.length);
    const r = await imp.finish();
    const day = (metric: string, d = '2024-03-10') => r.aggregates.find((a) => a.metric === metric && a.period === 'day' && a.day === d);

    // Steps 08–09: watch (600) beats iPhone (550) for the same hour; 12:00 iPhone only.
    expect(day('steps')?.sum).toBeCloseTo(900, 6);
    // Discrete: Apple Watch (2 readings) chosen over WHOOP (1) — no mixing.
    expect(day('heartRate')?.average).toBe(80);
    expect(day('heartRate')?.count).toBe(2);
    // High-volume types aren't stored raw; low-volume are (food deduped by id).
    expect((await sink.all('steps')).length).toBe(0);
    expect((await sink.all('heartRate')).length).toBe(0);
    expect((await sink.all('dietaryEnergy')).length).toBe(1);
    expect(day('dietaryEnergy')?.sum).toBe(380);
    // Weight lb → kg, manual flag kept.
    const w = (await sink.all('bodyMass'))[0];
    expect(w.value).toBeCloseTo(81.6466, 3);
    expect(w.isManual).toBe(true);
    // Sleep: watch wins 23:00–04:00, Oura fills 22:50–23:00 and 04:00–05:00.
    expect(day('sleep')?.sum).toBeCloseTo(370, 6);
    // Workouts: Watch + Garmin merged; Garmin's distance filled in; route flagged.
    const wk = await sink.all('workout');
    expect(wk.length).toBe(2);
    expect(day('workout')?.count).toBe(1);
    // Rings, profile, unknown types skipped.
    expect(r.rings[0]).toMatchObject({ day: '2024-03-10', move: 512.3, exerciseGoal: 30 });
    expect(r.me.biologicalSex).toBe('HKBiologicalSexFemale');
    expect(r.counts.skipped).toBeGreaterThanOrEqual(1);
    expect(r.sources.steps.map((s) => s.name).sort()).toEqual(["Alex's Apple Watch", "Alex's iPhone"]);
    // Intraday window (export date 2024-03-12) includes 03-10.
    const intra = r.intraday.find((d) => d.day === '2024-03-10')!;
    expect(intra.hr[8 * 60 + 10]).toBe(70);
    expect(intra.steps.reduce((a, b) => a + b, 0)).toBeGreaterThan(0);
    // Rollups exist.
    expect(r.aggregates.some((a) => a.metric === 'steps' && a.period === 'week')).toBe(true);
  });

  it('keeps memory bounded on a large synthetic export', async () => {
    // ~400k high-volume records (~90 MB of XML) generated on the fly.
    const N = 400_000;
    const enc = new TextEncoder();
    let i = 0;
    const header = '<?xml version="1.0"?><HealthData locale="en_US"><ExportDate value="2024-06-30 09:00:00 +0000"/>';
    const t0 = Date.parse('2014-01-01T00:00:00Z');
    const pad = (n: number) => String(n).padStart(2, '0');
    const fmt = (ms: number) => { const d = new Date(ms); return `${d.getUTCFullYear()}-${pad(d.getUTCMonth() + 1)}-${pad(d.getUTCDate())} ${pad(d.getUTCHours())}:${pad(d.getUTCMinutes())}:${pad(d.getUTCSeconds())} +0000`; };
    let bytes = 0;
    const stream = new ReadableStream<Uint8Array>({
      start(c) { c.enqueue(enc.encode(header)); },
      pull(c) {
        let s = '';
        for (let k = 0; k < 2000 && i < N; k++, i++) {
          const t = t0 + i * 15 * 60_000; // every 15 min for ~11 years
          const src = i % 3 === 0 ? "Alex's iPhone" : "Alex's Apple Watch";
          s += `<Record type="HKQuantityTypeIdentifierHeartRate" sourceName="${src}" unit="count/min" startDate="${fmt(t)}" endDate="${fmt(t)}" value="${60 + (i % 40)}"/>`;
          s += `<Record type="HKQuantityTypeIdentifierStepCount" sourceName="${src}" unit="count" startDate="${fmt(t)}" endDate="${fmt(t + 600_000)}" value="${i % 200}"/>`;
        }
        if (i >= N) s += '</HealthData>';
        const b = enc.encode(s);
        bytes += b.length;
        c.enqueue(b);
        if (i >= N) c.close();
      },
    });
    const sink = new MemorySink();
    const imp = new HealthImporter(sink, UTC);
    (globalThis as { gc?: () => void }).gc?.();
    const before = process.memoryUsage().heapUsed;
    const started = Date.now();
    await imp.parse(stream, 0);
    const r = await imp.finish();
    (globalThis as { gc?: () => void }).gc?.();
    const after = process.memoryUsage().heapUsed;
    const growthMB = (after - before) / 1024 / 1024;
    // eslint-disable-next-line no-console
    console.log(`synthetic import: ${(bytes / 1e6).toFixed(0)} MB XML, ${r.counts.records} records in ${Date.now() - started} ms, retained heap +${growthMB.toFixed(0)} MB`);
    expect(r.counts.records).toBe(2 * N);
    expect(sink.map.size).toBe(0); // nothing high-volume stored raw
    expect(r.aggregates.filter((a) => a.metric === 'heartRate' && a.period === 'day').length).toBeGreaterThan(4000);
    expect(growthMB).toBeLessThan(400);
  });
});
