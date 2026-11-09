import { describe, expect, it } from 'vitest';
import { fixture, iso } from './fixtures';
import { computeAll, hrvScore, durationScore, strainFromTRIMP, trimp, estimateMaxHR, acwr, fillDaily, fillSeries, type ScoreInputs } from '../scores';
import { sleepNights } from '../dedup';
import { SourcePriority } from '../source';
import { ianaZone, UTC, addDays } from '../daykey';
import type { Sample } from '../model';

const f = fixture('scores_cases.json');

// eslint-disable-next-line @typescript-eslint/no-explicit-any
function inputs(c: any): ScoreInputs {
  const zone = c.timeZone === 'UTC' ? UTC : ianaZone(c.timeZone);
  const dm = (o?: Record<string, number>) => new Map(Object.entries(o ?? {}));
  const src = { bundleId: 'com.apple.health.watch', name: 'Apple Watch' };
  const samples: Sample[] = (c.sleepSamples ?? []).map((s: [string, string, number], i: number) => ({
    id: `s${i}`, type: 'sleep', value: s[2], unit: 'stage', start: iso(s[0]), end: iso(s[1]), source: src, isManual: false, isEstimated: false }));
  const nights = new Map(sleepNights(samples, new SourcePriority(), zone).map((n) => [n.day, n]));
  return {
    day: c.day, zone, hrvBySource: Object.fromEntries(Object.entries(c.hrv ?? {}).map(([k, v]) => [k, dm(v as Record<string, number>)])),
    restingHR: dm(c.restingHR), nights, sleepGoalMinutes: c.sleepGoalMinutes ?? 480,
    heartRate: (c.heartRate ?? []).map((p: [string, number]) => ({ time: iso(p[0]), bpm: p[1] })),
    steps: (c.steps ?? []).map((p: [string, number]) => [iso(p[0]), p[1]]), workouts: (c.workouts ?? []).map((w: [string, string]) => [iso(w[0]), iso(w[1])]),
    loadHistory: dm(c.loadHistory), age: c.age ?? undefined, sex: c.sex ?? 'unknown', observedMaxHR: c.observedMaxHR ?? undefined, now: iso(c.now),
  };
}

describe('derived scores reproduce iOS (shared fixtures)', () => {
  for (const c of f.cases) {
    it(c.name, () => {
      const r = computeAll(inputs(c));
      for (const [kind, e] of Object.entries(c.expected as Record<string, Record<string, unknown>>)) {
        const got = r[kind as keyof typeof r];
        if (e.value === null || e.value === undefined) expect(got.value, `${kind} should be not-enough-data`).toBeUndefined();
        else expect(Math.abs(got.value! - (e.value as number)), `${kind} value ${got.value} vs ${e.value}`).toBeLessThanOrEqual(f.tolerance);
        expect(got.confidence, `${kind} confidence`).toBe(e.confidence);
        expect(got.isEstimated, `${kind} estimated`).toBe(e.isEstimated);
        expect(got.components.map((x) => x.name), `${kind} components`).toEqual(e.components);
        for (const k of ['trimp', 'acwr', 'start']) {
          if (e[k] !== undefined) expect(Math.abs(got.extras[k] - (e[k] as number)), `${kind} ${k}`).toBeLessThanOrEqual(f.tolerance);
        }
      }
    });
  }
});

describe('score behaviour', () => {
  it('mappings', () => {
    expect(hrvScore(0)).toBeCloseTo(64.566, 3);
    expect(durationScore(360, 480)).toBeCloseTo(100 * 0.75 ** 1.5, 9);
    expect(strainFromTRIMP(400)).toBeCloseTo(21, 9);
    expect(estimateMaxHR(40, 230)).toBe(195);
  });
  it('TRIMP', () => {
    const p = { maxHR: 190, restingHR: 60, sex: 'male' as const };
    const t0 = iso('2024-03-20T18:00:00Z');
    const pts = Array.from({ length: 31 }, (_, i) => ({ time: t0 + i * 60000, bpm: 138 }));
    expect(trimp(pts, p)).toBeCloseTo(30 * 0.6 * 0.64 * Math.exp(1.92 * 0.6), 6);
  });
  it('ACWR + gaps', () => {
    const day = '2024-03-20';
    const load = new Map([...Array(28).keys()].map((k) => [addDays(day, -k), k < 7 ? 120 : 100]));
    expect(acwr(load, day)!.ratio).toBeCloseTo(120 / 105, 9);
    const m = new Map([...Array(30).keys()].map((k) => [addDays(day, -(k + 1)), 50 + (k % 2 ? 1 : -1)]));
    expect(fillDaily(m, day, day).get(day)?.isEstimated).toBe(true);
    const t0 = iso('2024-03-20T08:00:00Z');
    expect(fillSeries([[t0, 60], [t0 + 3600_000, 80]]).filter((x) => x[2]).length).toBe(3);
  });
});
