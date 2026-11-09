import { describe, expect, it } from 'vitest';
import { close, fixture, toSample } from './fixtures';
import { dailyTotals, dedupeCumulative, mergeWorkouts, selectDiscrete, sleepNights, totalCumulative } from '../dedup';
import { SourcePriority } from '../source';
import { ianaZone, UTC } from '../daykey';
import { sourceKey, WORKOUT_KEYS } from '../model';

const f = fixture('dedup_cases.json');
const zone = (tz: string) => (tz === 'UTC' ? UTC : ianaZone(tz));
const STAGE: Record<string, number> = { core: 3, deep: 4, rem: 5, awake: 2, asleep: 1 };

describe('cumulative dedup (shared fixtures)', () => {
  for (const c of f.cumulative) {
    it(c.name, () => {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const samples = c.samples.map((s: any) => toSample(s, f.sources));
      const p = new SourcePriority(c.priority);
      expect(close(totalCumulative(samples, p), c.expectedTotal)).toBe(true);
      const daily = dailyTotals(samples, p, zone(c.timeZone));
      expect(daily.size).toBe(Object.keys(c.expectedDaily).length);
      for (const [k, v] of Object.entries(c.expectedDaily)) expect(close(daily.get(k), v as number)).toBe(true);
      const segs = dedupeCumulative(samples, p);
      for (let i = 1; i < segs.length; i++) expect(segs[i - 1].end).toBeLessThanOrEqual(segs[i].start);
    });
  }
});

describe('sleep merge (shared fixtures)', () => {
  for (const c of f.sleep) {
    it(c.name, () => {
      const src = c.samples ?? f.sleep[c.samplesFrom].samples;
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const nights = sleepNights(src.map((s: any) => toSample(s, f.sources)), new SourcePriority(c.priority), zone(c.timeZone));
      expect(nights.length).toBe(c.expected.nights);
      const n = nights[0];
      expect(n.day).toBe(c.expected.day);
      expect(close(n.asleepMinutes, c.expected.asleepMinutes)).toBe(true);
      expect(close(n.awakeMinutes, c.expected.awakeMinutes)).toBe(true);
      expect(close(n.inBedMinutes, c.expected.inBedMinutes)).toBe(true);
      expect(sourceKey(n.primarySource)).toBe(c.expected.primarySource);
      expect(n.hasStages).toBe(c.expected.hasStages);
      for (const [k, v] of Object.entries(c.expected.stageMinutes)) expect(close(n.stageMinutes[STAGE[k]], v as number)).toBe(true);
      const present = Object.entries(n.stageMinutes).filter(([, v]) => v > 0).map(([k]) => +k).sort();
      expect(present).toEqual(Object.keys(c.expected.stageMinutes).map((k) => STAGE[k]).sort());
    });
  }
});

describe('workout merge (shared fixtures)', () => {
  for (const c of f.workouts) {
    it(c.name, () => {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const merged = mergeWorkouts(c.samples.map((s: any) => toSample(s, f.sources)), new SourcePriority(c.priority));
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      expect(merged.map((m) => m.id)).toEqual(c.expected.map((e: any) => e.id));
      merged.forEach((m, i) => {
        const e = c.expected[i];
        expect(m.metadata?.[WORKOUT_KEYS.mergedFrom] ?? null).toBe(e.mergedFrom);
        if (e.energyKcal) expect(m.metadata?.[WORKOUT_KEYS.energy]).toBe(e.energyKcal);
        if (e.distanceM) expect(m.metadata?.[WORKOUT_KEYS.distance]).toBe(e.distanceM);
      });
    });
  }
});

describe('discrete source selection (shared fixtures)', () => {
  for (const c of f.discrete) {
    it(c.name, () => {
      const samples = Object.entries(c.counts as Record<string, number>).flatMap(([src, n]) =>
        Array.from({ length: n }, (_, i) => toSample({ id: `${src}${i}`, type: 'heartRate', value: 60, start: new Date(i * 60000).toISOString(), end: new Date(i * 60000).toISOString(), source: src }, f.sources)));
      const chosen = selectDiscrete(samples, c.preferred ?? undefined, new SourcePriority(c.priority));
      expect(new Set(chosen.map((s) => sourceKey(s.source)))).toEqual(new Set([c.expectedSource]));
    });
  }
});
