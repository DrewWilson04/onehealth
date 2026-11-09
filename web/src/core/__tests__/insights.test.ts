import { describe, expect, it } from 'vitest';
import { fixture } from './fixtures';
import { Stats, findingText, runInsights, studentTCDF, validateAndFill, withWorkoutFlags, type Features } from '../insights';

const f = fixture('insights_cases.json');
// eslint-disable-next-line @typescript-eslint/no-explicit-any
function features(c: any): Features {
  const base: Features = Object.fromEntries(Object.entries(c.series).map(([k, v]) => [k, new Map(Object.entries(v as Record<string, number>))]));
  const withFlags = withWorkoutFlags(base, c.workouts.map((w: [string, number]) => ({ day: w[0], endHour: w[1] })));
  delete (withFlags as Record<string, unknown>).weekend; // iOS fixture loader doesn't add weekend
  return withFlags;
}

describe('insights reproduce iOS (shared fixtures)', () => {
  for (const c of f.cases) {
    it(c.name, () => {
      const got = runInsights(features(c), c.today);
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      expect(new Set(got.map((x) => x.id))).toEqual(new Set(c.expected.map((e: any) => e.id)));
      for (const e of c.expected) {
        const g = got.find((x) => x.id === e.id)!;
        expect(findingText(g)).toBe(e.text);
        for (const k of ['effect', 'r', 'z', 'pct']) if (e[k] !== undefined) expect(Math.abs(g.numbers[k] - e[k])).toBeLessThanOrEqual(f.tolerance);
      }
    });
  }
});

describe('statistics', () => {
  it('t CDF, ranks, BH', () => {
    expect(studentTCDF(2.228, 10)).toBeCloseTo(0.975, 3);
    expect(Stats.spearman([1, 2, 3, 4, 5], [2, 4, 6, 8, 100])).toBeCloseTo(1, 12);
    expect(Stats.ranks([10, 20, 20, 30])).toEqual([1, 2.5, 2.5, 4]);
    expect(Stats.benjaminiHochberg([0.01, 0.04, 0.03, 0.5], 0.1)).toEqual(new Set([0, 1, 2]));
  });
  it('validation rejects invented numbers', () => {
    const t = { effect: '8 ms' };
    expect(validateAndFill('Down by [[effect]].', t)).toBe('Down by 8 ms.');
    expect(validateAndFill('Down by 10 ms.', t)).toBeUndefined();
    expect(validateAndFill('Down [[pct]].', t)).toBeUndefined();
  });
});
