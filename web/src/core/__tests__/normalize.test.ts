import { describe, expect, it } from 'vitest';
import { fixture, iso } from './fixtures';
import { Normalizer, parseDevice, parseHealthDate, stableId, type RawSample } from '../normalize';
import { inferVendor } from '../source';
import { METRICS } from '../model';

// eslint-disable-next-line @typescript-eslint/no-explicit-any
function raw(d: any): RawSample {
  const num = d.value !== undefined && d.value !== '' && !Number.isNaN(Number(d.value)) ? Number(d.value) : undefined;
  return {
    typeIdentifier: d.type, value: num, stringValue: num === undefined ? d.value : undefined, unit: d.unit,
    start: parseHealthDate(d.startDate)!, end: parseHealthDate(d.endDate)!, sourceName: d.sourceName, sourceBundleId: d.sourceBundleId ?? '',
    device: parseDevice(d.device), metadata: d.metadata ?? {},
  };
}

describe('normalizer (shared fixtures)', () => {
  const f = fixture('normalizer_cases.json');
  const n = new Normalizer('');
  for (const c of f.cases) {
    it(c.name, () => {
      const r = n.normalize(raw(c.raw));
      if (c.expected) {
        const s = r.sample!;
        expect(s).toBeDefined();
        expect(s.type).toBe(c.expected.type);
        expect(Math.abs(s.value - c.expected.value)).toBeLessThan(1e-3);
        expect(s.unit).toBe(c.expected.unit);
        expect(s.start).toBe(iso(c.expected.start));
        expect(s.end).toBe(iso(c.expected.end));
        expect(s.isManual).toBe(c.expected.isManual);
        expect(inferVendor(s.source, s.device)).toBe(c.expected.vendor);
        if (c.expected.deviceModel) expect(s.device?.model).toBe(c.expected.deviceModel);
        if (c.expected.deviceHardware) expect(s.device?.hardwareVersion).toBe(c.expected.deviceHardware);
      } else {
        expect(r.sample).toBeUndefined();
        expect(r.issue).toBe(c.expectedIssue);
      }
    });
  }
  it('stable id matches iOS', () => {
    expect(stableId(raw(f.stableId.raw))).toBe(f.stableId.expected);
  });
  it('parses health dates', () => {
    expect(parseHealthDate('2024-03-10 08:00:00 +0530')).toBe(iso('2024-03-10T02:30:00Z'));
    expect(parseHealthDate('garbage')).toBeUndefined();
  });
  it('registry is the iOS registry', () => {
    expect(METRICS.length).toBeGreaterThan(50);
    expect(new Set(METRICS.map((m) => m.id)).size).toBe(METRICS.length);
  });
});
