import { useApp } from './App';
import { useAsync, ChartTable } from './components';
import { scoreHistory, scoresFor } from '../data/services';
import { loadStatus, scoreLabel, type ScoreKind } from '../core/scores';
import { addDays } from '../core/daykey';
import { Area, AreaChart, CartesianGrid, Line, LineChart, ResponsiveContainer, Tooltip, XAxis, YAxis } from 'recharts';
import { fmtDay, scoreColor } from './format';
import { BRAND } from '../brand';

const TITLE: Record<ScoreKind, string> = { readiness: 'Readiness', sleep: 'Sleep Score', strain: 'Strain', energy: 'Energy' };

export function ScoreDetail({ kind }: { kind: ScoreKind }) {
  const { today, revision, info, settings } = useApp();
  const data = useAsync(async () => ({
    r: (await scoresFor(today, info, settings))[kind],
    hist: await scoreHistory(kind, addDays(today, kind === 'readiness' || kind === 'sleep' ? -29 : -13), today, info, settings),
  }), [kind, today, revision]);
  if (!data) return <p className="muted">Computing…</p>;
  const { r, hist } = data;
  const max = kind === 'strain' ? 21 : 100;
  return (
    <div>
      <h1>{TITLE[kind]}</h1>
      <section className="panel">
        {r.value !== undefined ? (
          <div style={{ fontSize: '3rem', fontWeight: 800, color: kind === 'strain' ? 'var(--orange)' : scoreColor(r.value) }}>
            {kind === 'strain' ? r.value.toFixed(1) : Math.round(r.value)} <span className="sub" style={{ fontSize: '1rem' }}>{scoreLabel(r)}</span>
          </div>
        ) : <><h2>Not enough data</h2><p>{r.reason}</p></>}
        <p className="sub">Confidence: {r.confidence}{r.isEstimated ? ' · includes estimated (gap-filled) values' : ''}</p>
        <p className="sub">{BRAND.name}'s own estimate from your raw data — not equivalent to WHOOP, Garmin or Oura scores. Not medical advice.</p>
      </section>
      {kind === 'energy' && r.series && r.series.length > 1 && (
        <section className="panel">
          <h2 style={{ marginTop: 0 }}>Through the day</h2>
          <div className="chart" role="img" aria-label={`Energy from ${Math.round(r.series[0])} to ${Math.round(r.series[r.series.length - 1])}`}>
            <ResponsiveContainer><AreaChart data={r.series.map((v, i) => ({ i, v }))}>
              <XAxis dataKey="i" hide /><YAxis domain={[0, 100]} width={32} /><Area isAnimationActive={false} dataKey="v" stroke="var(--green)" fill="var(--green)" fillOpacity={0.2} />
            </AreaChart></ResponsiveContainer>
          </div>
          <div className="row"><span>Charged overnight to</span><span>{Math.round(r.extras.start ?? 0)}</span></div>
          <div className="row"><span>Drained</span><span>{Math.round(r.extras.drained ?? 0)}</span></div>
          <div className="row"><span>Recharged while resting</span><span>{Math.round(r.extras.charged ?? 0)}</span></div>
        </section>
      )}
      {kind === 'strain' && (
        <section className="panel">
          <h2 style={{ marginTop: 0 }}>Training load</h2>
          <div className="row"><span>Acute : chronic ratio</span><span>{r.extras.acwr?.toFixed(2) ?? '—'}</span></div>
          <p><strong>{loadStatus(r.extras.acwr)}</strong></p>
          {r.extras.trimp !== undefined && <div className="row"><span>TRIMP</span><span>{Math.round(r.extras.trimp)}</span></div>}
          {[1, 2, 3, 4, 5].map((z) => r.extras[`zone${z}`] >= 1 && <div className="row" key={z}><span>Zone {z}</span><span>{Math.round(r.extras[`zone${z}`])} min</span></div>)}
        </section>
      )}
      {r.components.length > 0 && (
        <section className="panel">
          <h2 style={{ marginTop: 0 }}>What went into it</h2>
          {r.components.map((c) => (
            <div className="row" key={c.name}><span>{c.name}{c.isEstimated ? ' ✨' : ''}</span><span>{Math.round(c.score)} <span className="sub">· {Math.round(c.weight * 100)}%</span></span></div>
          ))}
        </section>
      )}
      <section className="panel">
        <h2 style={{ marginTop: 0 }}>Inputs</h2>
        {r.inputsUsed.map((x) => <div key={x}>✅ {x}</div>)}
        {r.missingInputs.map((x) => <div key={x} className="muted">➖ {x}</div>)}
      </section>
      <section className="panel">
        <h2 style={{ marginTop: 0 }}>History</h2>
        <div className="chart" role="img" aria-label={`${TITLE[kind]} history`}>
          <ResponsiveContainer><LineChart data={hist.map((h) => ({ x: fmtDay(h.day, { month: 'short', day: 'numeric' }), v: h.value }))}>
            <CartesianGrid strokeDasharray="3 3" vertical={false} stroke="var(--border)" />
            <XAxis dataKey="x" tick={{ fontSize: 11 }} minTickGap={16} /><YAxis domain={[0, max]} width={32} /><Tooltip />
            <Line isAnimationActive={false} dataKey="v" stroke="var(--green)" connectNulls={false} dot={{ r: 2 }} />
          </LineChart></ResponsiveContainer>
        </div>
        <ChartTable caption={`${TITLE[kind]} history`} rows={hist.map((h) => [fmtDay(h.day), h.value === undefined ? 'not enough data' : String(Math.round(h.value))])} />
      </section>
    </div>
  );
}
