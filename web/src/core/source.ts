// Vendor inference + source priority — mirror of PulseCore Source.swift / SourcePriority.swift.
import type { DeviceRef, SourceRef } from './model';
import { sourceKey } from './model';

export type Vendor = 'appleWatch' | 'iPhone' | 'garmin' | 'whoop' | 'oura' | 'fitbit' | 'polar' | 'withings' | 'coros'
  | 'suunto' | 'samsung' | 'eightSleep' | 'strava' | 'pulseBoard' | 'other';

export const VENDOR_NAME: Record<Vendor, string> = {
  appleWatch: 'Apple Watch', iPhone: 'iPhone', garmin: 'Garmin', whoop: 'WHOOP', oura: 'Oura', fitbit: 'Fitbit', polar: 'Polar',
  withings: 'Withings', coros: 'COROS', suunto: 'Suunto', samsung: 'Samsung', eightSleep: 'Eight Sleep', strava: 'Strava',
  pulseBoard: 'PulseBoard', other: 'Other',
};

const RANK: Record<Vendor, number> = {
  appleWatch: 10, garmin: 20, whoop: 20, oura: 20, fitbit: 20, polar: 20, coros: 20, suunto: 20, samsung: 20,
  withings: 25, eightSleep: 25, iPhone: 30, pulseBoard: 35, strava: 40, other: 50,
};

export function inferVendor(source: SourceRef, device?: DeviceRef, ownPrefix = ''): Vendor {
  const hay = [source.bundleId, source.name, device?.name ?? '', device?.manufacturer ?? '', device?.model ?? ''].join(' ').toLowerCase();
  if (ownPrefix && hay.includes(ownPrefix.toLowerCase())) return 'pulseBoard';
  if (hay.includes('garmin')) return 'garmin';
  if (hay.includes('whoop')) return 'whoop';
  if (hay.includes('oura')) return 'oura';
  if (hay.includes('fitbit') || hay.includes('google fit') || hay.includes('com.google.android.apps.fitness')) return 'fitbit';
  if (hay.includes('polar')) return 'polar';
  if (hay.includes('withings') || hay.includes('nokia health')) return 'withings';
  if (hay.includes('coros')) return 'coros';
  if (hay.includes('suunto')) return 'suunto';
  if (hay.includes('samsung') || hay.includes('galaxy')) return 'samsung';
  if (hay.includes('eight sleep') || hay.includes('eightsleep')) return 'eightSleep';
  if (hay.includes('strava')) return 'strava';
  if (hay.includes('watch') && (hay.includes('apple') || source.bundleId.startsWith('com.apple.health'))) return 'appleWatch';
  if (device?.model?.toLowerCase().includes('watch')) return 'appleWatch';
  if (hay.includes('iphone') || device?.model?.toLowerCase().includes('iphone')) return 'iPhone';
  if (source.bundleId.startsWith('com.apple.health')) return 'iPhone';
  return 'other';
}

export class SourcePriority {
  constructor(public ordered: string[] = []) {}
  rank(s: SourceRef, d?: DeviceRef): number {
    const i = this.ordered.indexOf(sourceKey(s));
    if (i >= 0) return i;
    const j = this.ordered.indexOf(s.name);
    if (j >= 0) return j;
    return 1000 + RANK[inferVendor(s, d)];
  }
  isHigher(a: SourceRef, ad: DeviceRef | undefined, b: SourceRef, bd: DeviceRef | undefined): boolean {
    const ra = this.rank(a, ad), rb = this.rank(b, bd);
    if (ra !== rb) return ra < rb;
    return sourceKey(a) < sourceKey(b);
  }
  preferring(key?: string): SourcePriority {
    if (!key) return this;
    return new SourcePriority([key, ...this.ordered.filter((k) => k !== key)]);
  }
}

/** Swift tuple ordering on (rank, key[, spec]). */
export function lexLess(a: (number | string)[], b: (number | string)[]): boolean {
  for (let i = 0; i < a.length; i++) {
    if (a[i] < b[i]) return true;
    if (a[i] > b[i]) return false;
  }
  return false;
}
