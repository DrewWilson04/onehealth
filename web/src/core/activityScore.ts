// Mirror of PulseCore ActivityScore (docs/challenges.md).
export interface ActivityInputs { steps?: number; exerciseMinutes?: number; zoneMinutes: Record<number, number>; workoutMinutes?: number; sleepMinutes?: number }
const ZW: Record<number, number> = { 1: 0.5, 2: 1, 3: 1.5, 4: 2, 5: 2.5 };
const r2 = (v: number) => Math.round(v * 100) / 100;

export function activityBreakdown(i: ActivityInputs) {
  const steps = (30 * Math.min(i.steps ?? 0, 15000)) / 15000;
  const zoneActive = [2, 3, 4, 5].reduce((t, z) => t + (i.zoneMinutes[z] ?? 0), 0);
  const active = Math.max(i.exerciseMinutes ?? 0, zoneActive);
  const activePts = (30 * Math.min(active, 90)) / 90;
  let weighted = Object.entries(i.zoneMinutes).reduce((t, [z, m]) => t + m * (ZW[+z] ?? 0), 0);
  if (!Object.keys(i.zoneMinutes).length) weighted = i.workoutMinutes ?? 0;
  const intensity = (25 * Math.min(weighted, 120)) / 120;
  let sleep = 0;
  const s = i.sleepMinutes;
  if (s !== undefined) { if (s >= 420 && s <= 540) sleep = 15; else if ((s >= 360 && s < 420) || (s > 540 && s <= 600)) sleep = 7; }
  const b = { steps: r2(steps), activeMinutes: r2(activePts), intensity: r2(intensity), sleep };
  return { ...b, total: Math.round((b.steps + b.activeMinutes + b.intensity + b.sleep) * 100) / 100 };
}
