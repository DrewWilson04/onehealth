import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import type { Sample } from '../model';
import { metric } from '../model';

const dir = join(dirname(fileURLToPath(import.meta.url)), '../../../../docs/fixtures');
// eslint-disable-next-line @typescript-eslint/no-explicit-any
export const fixture = (name: string): any => JSON.parse(readFileSync(join(dir, name), 'utf8'));
export const iso = (s: string) => Date.parse(s);

export interface FixtureSource { sourceName: string; sourceBundleId: string; deviceModel?: string; deviceManufacturer?: string }
// eslint-disable-next-line @typescript-eslint/no-explicit-any
export function toSample(f: any, sources: Record<string, FixtureSource>): Sample {
  const src = sources[f.source];
  return {
    id: f.id, type: f.type, value: f.value, unit: metric(f.type)?.unit ?? 'count', start: iso(f.start), end: Math.max(iso(f.start), iso(f.end)),
    source: { bundleId: src.sourceBundleId, name: src.sourceName },
    device: src.deviceModel || src.deviceManufacturer ? { model: src.deviceModel, manufacturer: src.deviceManufacturer } : undefined,
    isManual: f.isManual ?? false, isEstimated: f.isEstimated ?? false, metadata: f.metadata,
  };
}
export const close = (a: number | undefined, b: number, eps = 1e-4) => a !== undefined && Math.abs(a - b) <= eps;
