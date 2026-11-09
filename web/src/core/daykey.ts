// Calendar days as integers (days since 1970-01-01) + "yyyy-MM-dd" keys.
// Mirrors PulseCore DayKey (julian-day arithmetic; DST-safe).

export type DayKey = string;
const MS_DAY = 86_400_000;

export function epochDayToKey(d: number): DayKey {
  const dt = new Date(d * MS_DAY);
  const y = dt.getUTCFullYear(), m = dt.getUTCMonth() + 1, day = dt.getUTCDate();
  return `${String(y).padStart(4, '0')}-${String(m).padStart(2, '0')}-${String(day).padStart(2, '0')}`;
}

export function keyToEpochDay(k: DayKey): number {
  const [y, m, d] = k.split('-').map(Number);
  return Math.round(Date.UTC(y, m - 1, d) / MS_DAY);
}

export const addDays = (k: DayKey, n: number) => epochDayToKey(keyToEpochDay(k) + n);
export const daysBetween = (a: DayKey, b: DayKey) => keyToEpochDay(b) - keyToEpochDay(a);
/** ISO weekday 1 = Mon … 7 = Sun. */
export const isoWeekday = (k: DayKey) => ((keyToEpochDay(k) + 3) % 7 + 7) % 7 + 1;
export const weekStart = (k: DayKey) => addDays(k, -(isoWeekday(k) - 1));
export const monthStart = (k: DayKey) => k.slice(0, 8) + '01';
export const yearStart = (k: DayKey) => k.slice(0, 5) + '01-01';
export function range(from: DayKey, to: DayKey): DayKey[] {
  const a = keyToEpochDay(from), b = keyToEpochDay(to);
  const out: DayKey[] = [];
  for (let d = a; d <= b; d++) out.push(epochDayToKey(d));
  return out;
}

/** A time zone = function from epoch ms to UTC offset (minutes). */
export interface Zone { offsetMinutes(ms: number): number; id: string }

export const UTC: Zone = { id: 'UTC', offsetMinutes: () => 0 };

/** Browser local time (fast path: Date.getTimezoneOffset). */
export const LOCAL: Zone = { id: 'local', offsetMinutes: (ms) => -new Date(ms).getTimezoneOffset() };

/** Arbitrary IANA zone via Intl (cached per hour). Used by tests. */
export function ianaZone(tz: string): Zone {
  const fmt = new Intl.DateTimeFormat('en-US', { timeZone: tz, hourCycle: 'h23', year: 'numeric', month: 'numeric', day: 'numeric', hour: 'numeric', minute: 'numeric', second: 'numeric' });
  const cache = new Map<number, number>();
  return {
    id: tz,
    offsetMinutes(ms: number) {
      const h = Math.floor(ms / 3_600_000);
      const c = cache.get(h);
      if (c !== undefined) return c;
      const p = Object.fromEntries(fmt.formatToParts(new Date(h * 3_600_000)).map((x) => [x.type, x.value]));
      const asUTC = Date.UTC(+p.year, +p.month - 1, +p.day, +p.hour, +p.minute, +p.second);
      const off = Math.round((asUTC - h * 3_600_000) / 60_000);
      cache.set(h, off);
      return off;
    },
  };
}

export const epochDayOf = (ms: number, z: Zone) => Math.floor((ms + z.offsetMinutes(ms) * 60_000) / MS_DAY);
export const dayKeyOf = (ms: number, z: Zone) => epochDayToKey(epochDayOf(ms, z));

/** Start of a local day in epoch ms. */
export function dayStartMs(k: DayKey, z: Zone): number {
  const guess = keyToEpochDay(k) * MS_DAY;
  let t = guess - z.offsetMinutes(guess) * 60_000;
  t = guess - z.offsetMinutes(t) * 60_000;
  return t;
}
export const localHour = (ms: number, z: Zone) => Math.floor((((ms + z.offsetMinutes(ms) * 60_000) % MS_DAY) + MS_DAY) % MS_DAY / 3_600_000);
export const localMinuteOfDay = (ms: number, z: Zone) => Math.floor((((ms + z.offsetMinutes(ms) * 60_000) % MS_DAY) + MS_DAY) % MS_DAY / 60_000);
