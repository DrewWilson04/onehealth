// Mirror of PulseCore Insights (Stats + InsightsEngine + FormatToken). See /docs/insights.md.
import { type DayKey, addDays, isoWeekday } from './daykey';
import { metric } from './model';

// ── Statistics ──────────────────────────────────────────────────────────
export const Stats = {
  mean: (x: number[]) => (x.length ? x.reduce((a, b) => a + b, 0) / x.length : NaN),
  variance(x: number[]) {
    if (x.length < 2) return 0;
    const m = Stats.mean(x);
    return x.reduce((t, v) => t + (v - m) ** 2, 0) / (x.length - 1);
  },
  sd: (x: number[]) => Math.sqrt(Stats.variance(x)),
  ranks(x: number[]) {
    const idx = x.map((_, i) => i).sort((a, b) => x[a] - x[b]);
    const r = new Array(x.length).fill(0);
    let i = 0;
    while (i < idx.length) {
      let j = i;
      while (j + 1 < idx.length && x[idx[j + 1]] === x[idx[i]]) j++;
      const avg = (i + j) / 2 + 1;
      for (let k = i; k <= j; k++) r[idx[k]] = avg;
      i = j + 1;
    }
    return r;
  },
  pearson(x: number[], y: number[]) {
    if (x.length !== y.length || x.length <= 2) return NaN;
    const mx = Stats.mean(x), my = Stats.mean(y);
    let sxy = 0, sxx = 0, syy = 0;
    for (let i = 0; i < x.length; i++) { sxy += (x[i] - mx) * (y[i] - my); sxx += (x[i] - mx) ** 2; syy += (y[i] - my) ** 2; }
    return sxx > 0 && syy > 0 ? sxy / Math.sqrt(sxx * syy) : NaN;
  },
  spearman: (x: number[], y: number[]) => Stats.pearson(Stats.ranks(x), Stats.ranks(y)),
  correlationPValue(r: number, n: number) {
    if (n <= 2 || !Number.isFinite(r)) return 1;
    if (Math.abs(r) >= 1) return 0;
    const t = r * Math.sqrt((n - 2) / (1 - r * r));
    return 2 * (1 - studentTCDF(Math.abs(t), n - 2));
  },
  welch(a: number[], b: number[]) {
    if (a.length < 2 || b.length < 2) return { t: 0, df: 0, p: 1 };
    const va = Stats.variance(a) / a.length, vb = Stats.variance(b) / b.length;
    const se = Math.sqrt(va + vb);
    if (se <= 0) return { t: 0, df: 0, p: Stats.mean(a) === Stats.mean(b) ? 1 : 0 };
    const t = (Stats.mean(a) - Stats.mean(b)) / se;
    const df = (va + vb) ** 2 / (va * va / (a.length - 1) + vb * vb / (b.length - 1));
    return { t, df, p: 2 * (1 - studentTCDF(Math.abs(t), df)) };
  },
  benjaminiHochberg(p: number[], q: number): Set<number> {
    const order = p.map((_, i) => i).sort((a, b) => p[a] - p[b]);
    let k = -1;
    order.forEach((i, rank) => { if (p[i] <= ((rank + 1) / p.length) * q) k = rank; });
    return new Set(k >= 0 ? order.slice(0, k + 1) : []);
  },
};

// Lanczos log-gamma (matches libm lgamma to ~1e-14 for our ranges).
function lgamma(x: number): number {
  const g = 7;
  const c = [0.99999999999980993, 676.5203681218851, -1259.1392167224028, 771.32342877765313, -176.61502916214059,
    12.507343278686905, -0.13857109526572012, 9.9843695780195716e-6, 1.5056327351493116e-7];
  if (x < 0.5) return Math.log(Math.PI / Math.abs(Math.sin(Math.PI * x))) - lgamma(1 - x);
  x -= 1;
  let a = c[0];
  const t = x + g + 0.5;
  for (let i = 1; i < g + 2; i++) a += c[i] / (x + i);
  return 0.5 * Math.log(2 * Math.PI) + (x + 0.5) * Math.log(t) - t + Math.log(a);
}
function betaCF(x: number, a: number, b: number) {
  const eps = 3e-14, fpmin = 1e-300;
  const qab = a + b, qap = a + 1, qam = a - 1;
  let c = 1, d = 1 - (qab * x) / qap;
  if (Math.abs(d) < fpmin) d = fpmin;
  d = 1 / d;
  let h = d;
  for (let m = 1; m <= 200; m++) {
    const m2 = 2 * m;
    let aa = (m * (b - m) * x) / ((qam + m2) * (a + m2));
    d = 1 + aa * d; if (Math.abs(d) < fpmin) d = fpmin;
    c = 1 + aa / c; if (Math.abs(c) < fpmin) c = fpmin;
    d = 1 / d; h *= d * c;
    aa = (-(a + m) * (qab + m) * x) / ((a + m2) * (qap + m2));
    d = 1 + aa * d; if (Math.abs(d) < fpmin) d = fpmin;
    c = 1 + aa / c; if (Math.abs(c) < fpmin) c = fpmin;
    d = 1 / d;
    const del = d * c;
    h *= del;
    if (Math.abs(del - 1) < eps) break;
  }
  return h;
}
export function incompleteBeta(x: number, a: number, b: number) {
  if (x <= 0) return 0;
  if (x >= 1) return 1;
  const front = Math.exp(lgamma(a + b) - lgamma(a) - lgamma(b) + a * Math.log(x) + b * Math.log(1 - x));
  return x < (a + 1) / (a + b + 2) ? (front * betaCF(x, a, b)) / a : 1 - (front * betaCF(1 - x, b, a)) / b;
}
export function studentTCDF(t: number, df: number) {
  const ib = incompleteBeta(df / (df + t * t), df / 2, 0.5);
  return t >= 0 ? 1 - 0.5 * ib : 0.5 * ib;
}

// ── Formatting (locale-neutral) ─────────────────────────────────────────
export const grouped = (n: number) => (n < 0 ? '-' : '') + String(Math.abs(n)).replace(/\B(?=(\d{3})+(?!\d))/g, ',');
const fmt1 = (v: number) => v.toFixed(1);
/** Swift's Int(x.rounded()) rounds half away from zero. */
const roundHalfAway = (v: number) => (v < 0 ? -Math.round(-v) : Math.round(v));

export function featureName(f: string): string {
  const m: Record<string, string> = { sleepMinutes: 'sleep', restingHeartRate: 'resting heart rate', hrv: 'HRV', respiratoryRate: 'respiratory rate',
    wristTemperature: 'wrist temperature', bodyMass: 'weight', vo2Max: 'cardio fitness', activeEnergy: 'active energy', exerciseTime: 'exercise minutes',
    'score.readiness': 'readiness', steps: 'step count' };
  return m[f] ?? metric(f)?.displayName.toLowerCase() ?? f;
}
export function featureValue(v: number, f: string): string {
  switch (f) {
    case 'sleepMinutes': { const m = roundHalfAway(Math.abs(v)); return m >= 60 ? `${Math.floor(m / 60)}h ${m % 60}m` : `${m} min`; }
    case 'hrv': return `${roundHalfAway(v)} ms`;
    case 'restingHeartRate': case 'heartRate': return `${roundHalfAway(v)} bpm`;
    case 'respiratoryRate': return `${fmt1(v)} breaths/min`;
    case 'wristTemperature': return `${fmt1(v)} °C`;
    case 'bodyMass': return `${fmt1(v)} kg`;
    case 'vo2Max': return fmt1(v);
    case 'activeEnergy': return `${roundHalfAway(v)} kcal`;
    case 'exerciseTime': return `${roundHalfAway(v)} min`;
    case 'steps': return `${grouped(roundHalfAway(v))} steps`;
    case 'score.readiness': return `${roundHalfAway(v)} points`;
    default: return fmt1(v);
  }
}

// ── Engine ──────────────────────────────────────────────────────────────
export type FindingKind = 'conditional' | 'correlation' | 'anomaly' | 'trendChange';
export interface Finding {
  id: string; kind: FindingKind; outcome: string; driver?: string; template: string; values: Record<string, string>;
  numbers: Record<string, number>; pValue?: number; n: number; strength: number; day: DayKey;
}
export const fillTemplate = (t: string, v: Record<string, string>) => Object.entries(v).reduce((s, [k, x]) => s.split(`[[${k}]]`).join(x), t);
export const findingText = (f: Finding) => fillTemplate(f.template, f.values);

type Series = Map<DayKey, number>;
export type Features = Record<string, Series>;

const CONDITIONALS = [
  { id: 'lateWorkout-hrv', driver: 'lateWorkout', threshold: 1, outcome: 'hrv', lag: 1, minEffect: 2, hi: 'higher', lo: 'lower',
    template: 'Your HRV is [[effect]] [[direction]] the morning after late workouts (after 7 pm) — [[a]] vs [[b]] on other days.' },
  { id: 'steps8k-sleep', driver: 'steps', threshold: 8000, outcome: 'sleepMinutes', lag: 1, minEffect: 10, hi: 'longer', lo: 'shorter',
    template: 'You sleep [[effect]] [[direction]] after days with 8,000+ steps — [[a]] vs [[b]].' },
  { id: 'workout-sleep', driver: 'workoutDay', threshold: 1, outcome: 'sleepMinutes', lag: 1, minEffect: 10, hi: 'longer', lo: 'shorter',
    template: 'On nights after a workout you sleep [[effect]] [[direction]] — [[a]] vs [[b]].' },
  { id: 'caffeine-sleep', driver: 'caffeine', threshold: 200, outcome: 'sleepMinutes', lag: 1, minEffect: 10, hi: 'longer', lo: 'shorter',
    template: 'After days with 200 mg+ caffeine you sleep [[effect]] [[direction]] — [[a]] vs [[b]].' },
  { id: 'weekend-sleep', driver: 'weekend', threshold: 1, outcome: 'sleepMinutes', lag: 0, minEffect: 15, hi: 'longer', lo: 'shorter',
    template: 'You sleep [[effect]] [[direction]] on weekends — [[a]] vs [[b]] on weekdays.' },
  { id: 'lateBed-readiness', driver: 'bedtimeAfter18', threshold: 360, outcome: 'score.readiness', lag: 0, minEffect: 3, hi: 'higher', lo: 'lower',
    template: 'Readiness is [[effect]] [[direction]] after nights you fall asleep past midnight — [[a]] vs [[b]].' },
];
const CORRELATIONS = [
  { id: 'sleep-rhr', x: 'sleepMinutes', y: 'restingHeartRate', lag: 0, template: 'More sleep tends to go with a [[direction]] resting heart rate (correlation [[r]] over [[n]] days).' },
  { id: 'sleep-hrv', x: 'sleepMinutes', y: 'hrv', lag: 0, template: 'More sleep tends to go with [[direction]] HRV (correlation [[r]] over [[n]] days).' },
  { id: 'exercise-readiness', x: 'exerciseTime', y: 'score.readiness', lag: 1, template: 'More exercise minutes tend to be followed by [[direction]] readiness the next day (correlation [[r]] over [[n]] days).' },
];
const ANOMALY: [string, number][] = [['restingHeartRate', 1], ['hrv', -1], ['sleepMinutes', -1], ['respiratoryRate', 1], ['wristTemperature', 0], ['steps', 0]];
const TREND = ['steps', 'sleepMinutes', 'restingHeartRate', 'hrv', 'bodyMass', 'vo2Max', 'activeEnergy', 'exerciseTime'];

/** Adds derived flag features (workoutDay, lateWorkout, weekend) — same rules as InsightFeatures.build. */
export function withWorkoutFlags(f: Features, workouts: { day: DayKey; endHour: number }[]): Features {
  const late: Series = new Map(), wd: Series = new Map(), weekend: Series = new Map();
  const worn = [...(f.steps ?? new Map()).keys()];
  for (const d of worn) { late.set(d, 0); wd.set(d, 0); }
  for (const w of workouts) { wd.set(w.day, 1); if (w.endHour >= 19) late.set(w.day, 1); }
  for (const d of new Set([...worn, ...(f.sleepMinutes ?? new Map()).keys()])) weekend.set(d, isoWeekday(d) >= 6 ? 1 : 0);
  return { ...f, lateWorkout: late, workoutDay: wd, weekend };
}

export function runInsights(f: Features, today: DayKey): Finding[] {
  const from = addDays(today, -90);
  const series = (k: string): Series => new Map([...(f[k] ?? new Map())].filter(([d]) => d >= from && d <= today));
  const cands: [Finding, number][] = [];
  for (const c of CONDITIONALS) {
    const drv = series(c.driver), out = series(c.outcome);
    const a: number[] = [], b: number[] = [];
    for (const [d, x] of drv) {
      const y = out.get(addDays(d, c.lag));
      if (y === undefined) continue;
      (x >= c.threshold ? a : b).push(y);
    }
    if (a.length < 7 || b.length < 7) continue;
    const w = Stats.welch(a, b), ma = Stats.mean(a), mb = Stats.mean(b), effect = ma - mb;
    if (Math.abs(effect) < c.minEffect) continue;
    const fv = (v: number) => featureValue(v, c.outcome);
    cands.push([{ id: c.id, kind: 'conditional', outcome: c.outcome, driver: c.driver, template: c.template,
      values: { effect: fv(Math.abs(effect)), direction: effect >= 0 ? c.hi : c.lo, a: fv(ma), b: fv(mb), nA: String(a.length), nB: String(b.length) },
      numbers: { effect, meanA: ma, meanB: mb, nA: a.length, nB: b.length, p: w.p }, pValue: w.p, n: a.length + b.length,
      strength: Math.min(1, Math.abs(w.t) / 6), day: today }, w.p]);
  }
  for (const c of CORRELATIONS) {
    const xs = series(c.x), ys = series(c.y);
    const x: number[] = [], y: number[] = [];
    for (const [d, v] of [...xs].sort(([a], [b]) => (a < b ? -1 : 1))) {
      const w = ys.get(addDays(d, c.lag));
      if (w !== undefined) { x.push(v); y.push(w); }
    }
    if (x.length < 21) continue;
    const r = Stats.spearman(x, y);
    if (!Number.isFinite(r) || Math.abs(r) < 0.3) continue;
    const p = Stats.correlationPValue(r, x.length);
    const dir = c.y === 'restingHeartRate' ? (r < 0 ? 'lower' : 'higher') : (r > 0 ? 'higher' : 'lower');
    cands.push([{ id: c.id, kind: 'correlation', outcome: c.y, driver: c.x, template: c.template, values: { r: r.toFixed(2), n: String(x.length), direction: dir },
      numbers: { r, n: x.length, p }, pValue: p, n: x.length, strength: Math.abs(r), day: today }, p]);
  }
  const keep = Stats.benjaminiHochberg(cands.map((c) => c[1]), 0.1);
  const findings = cands.filter((_, i) => keep.has(i)).map((c) => c[0]);
  for (const [k, want] of ANOMALY) {
    const s = f[k] ?? new Map();
    const v = s.get(today);
    if (v === undefined) continue;
    const base = [...Array(30).keys()].map((i) => s.get(addDays(today, -(i + 1)))).filter((x): x is number => x !== undefined);
    if (base.length < 14) continue;
    const m = Stats.mean(base), sdv = Stats.sd(base);
    if (sdv <= 0) continue;
    const z = (v - m) / sdv;
    if (Math.abs(z) < 2.5 || !(want === 0 || (z > 0) === (want > 0))) continue;
    findings.push({ id: `anomaly-${k}`, kind: 'anomaly', outcome: k, template: "Today's [[metric]] ([[value]]) is unusually [[direction]] compared with your 30-day average of [[baseline]].",
      values: { metric: featureName(k), value: featureValue(v, k), baseline: featureValue(m, k), direction: z > 0 ? 'high' : 'low' },
      numbers: { value: v, baseline: m, z }, n: base.length, strength: Math.min(1, Math.abs(z) / 4), day: today });
  }
  for (const k of TREND) {
    const s = f[k] ?? new Map();
    const recent = [...Array(14).keys()].map((i) => s.get(addDays(today, -i))).filter((x): x is number => x !== undefined);
    const prior = [...Array(28).keys()].map((i) => s.get(addDays(today, -(14 + i)))).filter((x): x is number => x !== undefined);
    if (recent.length < 10 || prior.length < 14) continue;
    const w = Stats.welch(recent, prior), mr = Stats.mean(recent), mp = Stats.mean(prior);
    if (mp === 0) continue;
    const pct = (mr - mp) / Math.abs(mp);
    if (!(w.p < 0.01) || Math.abs(pct) < 0.05) continue;
    findings.push({ id: `trend-${k}`, kind: 'trendChange', outcome: k, template: 'Your [[metric]] has [[direction]] [[pct]] over the last two weeks — [[recent]] vs [[prior]] before.',
      values: { metric: featureName(k), direction: pct > 0 ? 'risen' : 'dropped', pct: `${Math.round(Math.abs(pct) * 100)}%`, recent: featureValue(mr, k), prior: featureValue(mp, k) },
      numbers: { recent: mr, prior: mp, pct, p: w.p }, pValue: w.p, n: recent.length + prior.length, strength: Math.min(1, Math.abs(w.t) / 6), day: today });
  }
  return findings.sort((a, b) => (b.strength - a.strength) || (a.id < b.id ? 1 : a.id > b.id ? -1 : 0));
}

/** Mirror of InsightValidation (used if a phrasing layer is ever added on web). */
export function validateAndFill(text: string, tokens: Record<string, string>): string | undefined {
  if (/\d/.test(text)) return undefined;
  let rest = text;
  for (;;) {
    const o = rest.indexOf('[[');
    if (o < 0) break;
    const c = rest.indexOf(']]', o + 2);
    if (c < 0) return undefined;
    if (!(rest.slice(o + 2, c) in tokens)) return undefined;
    rest = rest.slice(c + 2);
  }
  if (rest.includes(']]')) return undefined;
  return fillTemplate(text, tokens);
}
