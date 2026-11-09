import { useApp } from './App';
import { useAsync, ChartTable } from './components';
import { nights } from '../data/services';
import { addDays } from '../core/daykey';
import { nightEfficiency } from '../core/dedup';
import { parseAttribution } from '../core/model';
import { Bar, BarChart, CartesianGrid, Legend, ResponsiveContainer, Tooltip, XAxis, YAxis } from 'recharts';
import { duration, fmtDay, STAGE_COLOR } from './format';
import { StageBar } from './Dashboard';

export function SleepView() {
  const { today, revision, settings } = useApp();
  const ns = useAsync(() => nights(addDays(today, -13), today, settings), [today, revision]);
  if (!ns) return <p className="muted">Loading…</p>;
  const last = ns[ns.length - 1];
  const data = ns.map((n) => ({ x: fmtDay(n.day, { month: 'short', day: 'numeric' }), Deep: (n.stageMinutes[4] ?? 0) / 60, Core: (n.stageMinutes[3] ?? 0) / 60,
    REM: (n.stageMinutes[5] ?? 0) / 60, Asleep: (n.stageMinutes[1] ?? 0) / 60, Awake: (n.stageMinutes[2] ?? 0) / 60 }));
  return (
    <div>
      <h1 style={{ color: 'var(--sleep)' }}>Sleep</h1>
      {last && (
        <section className="panel">
          <h2 style={{ marginTop: 0 }}>Last night · {fmtDay(last.day)}</h2>
          <StageBar night={last} />
          <div className="row"><span>Asleep</span><span>{duration(last.asleepMinutes)}</span></div>
          <div className="row"><span>In bed</span><span>{duration(last.inBedMinutes)}</span></div>
          {nightEfficiency(last) !== undefined && <div className="row"><span>Efficiency</span><span>{Math.round(nightEfficiency(last)! * 100)}%</span></div>}
          <div className="row"><span>Sources</span><span>{last.sources.length > 1 ? `${last.sources.length} devices merged` : parseAttribution(last.primarySource.name || last.primarySource.bundleId).bundleId}</span></div>
          {!last.hasStages && <p className="sub">This night has no stage breakdown.</p>}
        </section>
      )}
      <section className="panel">
        <h2 style={{ marginTop: 0 }}>Last 14 nights</h2>
        {!ns.length ? <p className="muted">No sleep in this export.</p> : (
          <div className="chart" role="img" aria-label={`Sleep for ${ns.length} nights`}>
            <ResponsiveContainer>
              <BarChart data={data}>
                <CartesianGrid strokeDasharray="3 3" vertical={false} stroke="var(--border)" />
                <XAxis dataKey="x" tick={{ fontSize: 11 }} /><YAxis unit="h" tick={{ fontSize: 11 }} width={40} />
                <Tooltip formatter={(v: number) => duration(v * 60)} /><Legend />
                <Bar isAnimationActive={false} dataKey="Deep" stackId="s" fill={STAGE_COLOR[4]} /><Bar isAnimationActive={false} dataKey="Core" stackId="s" fill={STAGE_COLOR[3]} />
                <Bar isAnimationActive={false} dataKey="REM" stackId="s" fill={STAGE_COLOR[5]} /><Bar isAnimationActive={false} dataKey="Asleep" stackId="s" fill={STAGE_COLOR[1]} />
                <Bar isAnimationActive={false} dataKey="Awake" stackId="s" fill={STAGE_COLOR[2]} />
              </BarChart>
            </ResponsiveContainer>
          </div>
        )}
        <ChartTable caption="Sleep per night" rows={ns.map((n) => [fmtDay(n.day), duration(n.asleepMinutes)])} />
        <p className="sub">Overlapping sleep from several devices is merged; your highest-priority source wins for each part of the night.</p>
      </section>
    </div>
  );
}
