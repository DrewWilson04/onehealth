import { useApp } from './App';
import { useAsync, SourceBadge } from './components';
import { samples } from '../db/queries';
import { mergeWorkouts } from '../core/dedup';
import { SourcePriority } from '../core/source';
import { addDays, dayStartMs, LOCAL } from '../core/daykey';
import { attribution, WORKOUT_KEYS, metric } from '../core/model';
import { duration, fmtValue } from './format';

const NAMES: Record<string, string> = { traditionalStrengthTraining: 'Strength Training', functionalStrengthTraining: 'Functional Strength',
  highIntensityIntervalTraining: 'HIIT', mixedCardio: 'Mixed Cardio', coreTraining: 'Core Training', crossTraining: 'Cross Training' };
const name = (t: string) => NAMES[t] ?? t.charAt(0).toUpperCase() + t.slice(1).replace(/([a-z])([A-Z])/g, '$1 $2');

export function WorkoutsView() {
  const { today, revision, settings } = useApp();
  const ws = useAsync(async () => mergeWorkouts(await samples('workout', dayStartMs(addDays(today, -89), LOCAL), dayStartMs(addDays(today, 1), LOCAL)),
    new SourcePriority(settings.priority)).sort((a, b) => b.start - a.start), [today, revision]);
  const dist = metric('distanceWalkingRunning')!;
  return (
    <div>
      <h1 style={{ color: 'var(--activity)' }}>Workouts · last 90 days</h1>
      <section className="panel">
        {!ws?.length && <p className="muted">No workouts in this period.</p>}
        {ws?.map((w) => {
          const md = w.metadata ?? {};
          return (
            <div className="row" key={w.id}>
              <span><strong>{name(md[WORKOUT_KEYS.activityType] ?? 'other')}</strong><br />
                <span className="sub">{new Date(w.start).toLocaleString(undefined, { dateStyle: 'medium', timeStyle: 'short' })}</span>
                {md[WORKOUT_KEYS.mergedFrom] && <span className="sub"> · merged {md[WORKOUT_KEYS.mergedFrom].split(',').length} duplicate(s)</span>}</span>
              <span style={{ textAlign: 'right' }}>{duration(w.value)}
                {md[WORKOUT_KEYS.energy] && <> · {Math.round(Number(md[WORKOUT_KEYS.energy]))} kcal</>}
                {md[WORKOUT_KEYS.distance] && <> · {fmtValue(Number(md[WORKOUT_KEYS.distance]), dist)}</>}
                <br /><SourceBadge attribution={attribution(w.source)} /></span>
            </div>
          );
        })}
      </section>
    </div>
  );
}
