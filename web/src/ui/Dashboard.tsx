import { useApp } from './App';
import { useAsync, MetricCard, Rings, ScoreCard, Sparkline } from './components';
import { aggregates, latestAggregate, rings as getRings } from '../db/queries';
import { metric, SECTIONS, STAGE_LABEL } from '../core/model';
import { compare, pctChange, direction, points, streak } from '../core/aggregate';
import { addDays } from '../core/daykey';
import { nights, scoresFor, valueOf } from '../data/services';
import { href } from './router';
import { duration, fmtDay, fmtValue, STAGE_COLOR } from './format';

const CARD_METRICS = ['steps', 'activeEnergy', 'exerciseTime', 'restingHeartRate', 'hrv', 'bodyMass', 'water', 'dietaryEnergy'];

export function Dashboard() {
  const { today, revision, settings, info } = useApp();
  const data = useAsync(async () => {
    const out: Record<string, { value?: number; week: ReturnType<typeof points>; sub?: string; dir?: number; source?: string; est?: boolean }> = {};
    for (const id of CARD_METRICS) {
      const m = metric(id)!;
      const rows = await aggregates(id, 'day', addDays(today, -13), today);
      const latest = m.dailyStatistic === 'latest' ? await latestAggregate(id, today) : rows.find((r) => r.day === today);
      const c = compare(rows, m, 'week', today);
      const p = pctChange(c);
      out[id] = {
        value: valueOf(latest, id), week: points(rows.filter((r) => r.day >= addDays(today, -6)), m), source: latest?.primarySource, est: latest?.isEstimated,
        sub: m.dailyStatistic === 'latest' && latest && latest.day !== today ? fmtDay(latest.day)
          : p !== undefined ? `${p >= 0 ? '▲' : '▼'} ${Math.abs(Math.round(p * 100))}% vs last week` : undefined,
        dir: direction(c, m.higherIsBetter),
      };
    }
    const r = await getRings(today);
    const lastNight = (await nights(today, today, settings))[0];
    const scores = await scoresFor(today, info, settings);
    const goals = [];
    for (const g of settings.goals) {
      const m = metric(g.metric);
      if (!m) continue;
      const rows = await aggregates(g.metric, 'day', addDays(today, -400), today);
      goals.push({ g, m, s: streak(g, m, new Map(rows.filter((x) => !x.isEstimated).map((x) => [x.day, valueOf(x, g.metric)!]).filter(([, v]) => v !== undefined) as [string, number][]), today) });
    }
    return { out, r, lastNight, scores, goals };
  }, [today, revision]);

  if (!data) return <p className="muted">Loading your dashboard…</p>;
  const { out, r, lastNight, scores, goals } = data;
  return (
    <div>
      <h1>{fmtDay(today, { weekday: 'long', month: 'long', day: 'numeric' })}</h1>
      <div className="grid">
        <div className="card wide">
          <div className="title" style={{ color: 'var(--vermillion)' }}>Activity rings</div>
          {r ? (
            <div style={{ display: 'flex', gap: 16, alignItems: 'center' }}>
              <Rings rings={[{ label: 'Move', progress: r.moveGoal ? r.move / r.moveGoal : 0, color: '#D55E00' },
                { label: 'Exercise', progress: r.exerciseGoal ? r.exercise / r.exerciseGoal : 0, color: '#009E73' },
                { label: 'Stand', progress: r.standGoal ? r.stand / r.standGoal : 0, color: '#56B4E9' }]} />
              <div className="sub" style={{ fontSize: '.9rem' }}>
                <div><strong style={{ color: '#D55E00' }}>Move</strong> {Math.round(r.move)}/{Math.round(r.moveGoal)} kcal</div>
                <div><strong style={{ color: '#009E73' }}>Exercise</strong> {Math.round(r.exercise)}/{Math.round(r.exerciseGoal)} min</div>
                <div><strong style={{ color: '#56B4E9' }}>Stand</strong> {Math.round(r.stand)}/{Math.round(r.standGoal)} h</div>
              </div>
            </div>
          ) : <div className="sub">No activity summary for this day (rings need an Apple Watch).</div>}
        </div>
        <ScoreCard r={scores.readiness} />
        <ScoreCard r={scores.sleep} />
        <ScoreCard r={scores.strain} />
        <ScoreCard r={scores.energy} />
        <a className="card wide" href={href('sleep')}>
          <div className="title" style={{ color: 'var(--sleep)' }}>Last night</div>
          {lastNight ? (
            <>
              <div className="value">{duration(lastNight.asleepMinutes)} <span className="sub">asleep</span></div>
              <StageBar night={lastNight} />
            </>
          ) : <div className="sub">No sleep recorded</div>}
        </a>
        {CARD_METRICS.map((id) => (
          <MetricCard key={id} m={metric(id)!} value={out[id].value} week={out[id].week} source={out[id].source} estimated={out[id].est}
            sub={out[id].sub ? <span className={out[id].dir! > 0 ? 'up' : out[id].dir! < 0 ? 'down' : ''}>{out[id].sub}</span> : undefined} />
        ))}
        <div className="card wide">
          <div className="title" style={{ color: 'var(--orange)' }}>Goals & streaks</div>
          {goals.map(({ g, m, s }) => (
            <div key={g.id} className="row" style={{ alignItems: 'center' }}>
              <span>{m.displayName}</span>
              <span className="sub">{fmtValue(s.currentValue, m)} / {fmtValue(g.target, m)}</span>
              <span aria-label={`streak ${s.current} ${g.period === 'day' ? 'days' : 'weeks'}`}>🔥 {s.current} <span className="sub">best {s.longest}</span></span>
            </div>
          ))}
        </div>
      </div>
      <h2>Browse</h2>
      <div className="grid">
        {SECTIONS.map((s) => <a key={s.id} className="card" style={{ minHeight: 0 }} href={href('section', s.id)}><div className="title">{s.title}</div></a>)}
        <a className="card" style={{ minHeight: 0 }} href={href('workouts')}><div className="title">Workouts</div></a>
      </div>
    </div>
  );
}

export function StageBar({ night }: { night: { start: number; end: number; segments: { start: number; end: number; value: number }[]; stageMinutes: Record<number, number> } }) {
  const total = night.end - night.start;
  return (
    <>
      <svg width="100%" height="34" viewBox="0 0 1000 34" preserveAspectRatio="none" role="img"
        aria-label={Object.entries(night.stageMinutes).map(([k, v]) => `${STAGE_LABEL[+k]} ${duration(v)}`).join(', ')}>
        {night.segments.map((s, i) => {
          const lvl = s.value === 2 ? 0 : s.value === 5 ? 1 : s.value === 4 ? 3 : 2;
          return <rect key={i} x={((s.start - night.start) / total) * 1000} width={Math.max(1, ((s.end - s.start) / total) * 1000)} y={lvl * 8} height={8} fill={STAGE_COLOR[s.value]} />;
        })}
      </svg>
      <div className="sub">{Object.entries(night.stageMinutes).filter(([, v]) => v > 0).map(([k, v]) => `${STAGE_LABEL[+k]} ${duration(v)}`).join(' · ')}</div>
    </>
  );
}

export { Sparkline };
