import type { Progress } from './importer';
import type { ImportInfo } from '../db/queries';

export type ToWorker =
  | { kind: 'import'; file: File; priority: string[]; preferred: Record<string, string> }
  | { kind: 'cancel' };

export type FromWorker =
  | { kind: 'progress'; progress: Progress }
  | { kind: 'done'; info: ImportInfo }
  | { kind: 'error'; message: string };
