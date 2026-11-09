import { useApp } from './App';
import { useAsync, MetricCard } from './components';
import { aggregates, latestAggregate } from '../db/queries';
import { metricsIn, SECTIONS, type Section } from '../core/model';
import { points } from '../core/aggregate';
import { addDays } from '../core/daykey';
import { valueOf } from '../data/services';
import { href } from './router';
import { fmtDay } from './format';

export function SectionView({ id }: { id: string }) {
  const { today, revision } = useApp();
  const section = SECTIONS.find((s) => s.id === id);
  const data = useAsync(async () => {
    const rows = [];
    for (const m of metricsIn(id as Section)) {
      const latest = await latestAggregate(m.id, today);
      if (!latest) { rows.push({ m, missing: true as const }); continue; }
      const week = points(await aggregates(m.id, 'day', addDays(today, -6), today), m);
      const shown = m.dailyStatistic === 'latest' ? latest : (latest.day === today ? latest : undefined);
      rows.push({ m, missing: false as const, value: valueOf(shown, m.id), week, latest });
    }
    return rows;
  }, [id, today, revision]);
  if (!section) return <p>Unknown section.</p>;
  return (
    <div>
      <h1>{section.title}</h1>
      {id === 'sleep' && <p><a href={href('sleep')}>Sleep nights & stages →</a></p>}
      {id === 'activity' && <p><a href={href('workouts')}>Workouts →</a></p>}
      <div className="grid">
        {data?.filter((r) => !r.missing).map((r) => r.missing ? null : (
          <MetricCard key={r.m.id} m={r.m} value={r.value} week={r.week} source={r.latest.primarySource} estimated={r.latest.isEstimated}
            sub={r.value === undefined ? `Last: ${fmtDay(r.latest.day)}` : undefined} />
        ))}
      </div>
      {data && data.some((r) => r.missing) && (
        <p className="sub" style={{ marginTop: '1rem' }}>Not in this export: {data.filter((r) => r.missing).map((r) => r.m.displayName).join(', ')}. Some metrics are only recorded by certain devices.</p>
      )}
    </div>
  );
}
