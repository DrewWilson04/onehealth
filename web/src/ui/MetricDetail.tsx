import { useState } from 'react';
import { Bar, CartesianGrid, ComposedChart, Line, ReferenceLine, ResponsiveContainer, Scatter, Tooltip, XAxis, YAxis, ErrorBar } from 'recharts';
import { useApp } from './App';
import { useAsync, ChartTable } from './components';
import { aggregates, earliestDay } from '../db/queries';
import { metric } from '../core/model';
import { compare, pctChange, direction, personalBests, points, rollingAverage, rollupPoints, summary, RANGE_BUCKET, RANGE_DAYS, type TrendRange } from '../core/aggregate';
import { addDays } from '../core/daykey';
import { fmtDay, fmtValue, SECTION_COLOR } from './format';
import { patterns } from '../data/services';
import { findingText } from '../core/insights';

const RANGES: TrendRange[] = ['D', 'W', 'M', '6M', 'Y', 'All'];

export function MetricDetail({ id }: { id: string }) {
  const m = metric(id);
  const { today, revision, settings } = useApp();
  const [range, setRange] = useState<TrendRange>('W');
  const [showAvg, setShowAvg] = useState(true);
  const data = useAsync(async () => {
    if (!m) return undefined;
    const earliest = (await earliestDay(id)) ?? today;
    const days = RANGE_DAYS[range];
    const from = days ? addDays(today, -(days - 1)) : earliest;
    const daily = await aggregates(id, 'day', from, today);
    const bucket = RANGE_BUCKET[range];
    let pts;
    let perDay = false;
    if (bucket === 'hour') pts = points(await aggregates(id, 'hour', today, today), m);
    else if (bucket === 'day') pts = points(daily, m);
    else { perDay = ['sum', 'durationMinutes', 'count'].includes(m.dailyStatistic); pts = rollupPoints(await aggregates(id, bucket, from, today), m, perDay); }
    const rolling = range === 'W' || range === 'M' ? rollingAverage(points(await aggregates(id, 'day', addDays(from, -6), today), m), 7).filter((p) => p.day >= from) : [];
    const recent = await aggregates(id, 'day', addDays(today, -70), today);
    const all = await aggregates(id, 'day', earliest, today);
    const bests = personalBests(all, await aggregates(id, 'week', earliest, today), await aggregates(id, 'month', earliest, today), m);
    const key = id === 'sleep' ? 'sleepMinutes' : id;
    const notes = (await patterns(today, settings)).filter((f) => (f.kind === 'anomaly' || f.kind === 'trendChange') && f.outcome === key);
    return { pts, rolling, sum: summary(daily, m), week: compare(recent, m, 'week', today), month: compare(recent, m, 'month', today), bests, perDay, from, notes };
  }, [id, range, today, revision]);

  if (!m) return <p>Unknown metric.</p>;
  const color = SECTION_COLOR[m.section];
  const isSum = ['sum', 'durationMinutes', 'count'].includes(m.dailyStatistic);
  const bars = m.kind === 'cumulative' || m.kind === 'workout' || m.kind === 'category';
  const label = (p: { day: string; hour?: number }) => (p.hour !== undefined ? `${String(p.hour).padStart(2, '0')}:00` : RANGE_BUCKET[range] === 'month' ? fmtDay(p.day, { month: 'short', year: 'numeric' }) : fmtDay(p.day, { month: 'short', day: 'numeric' }));
  const rollByDay = new Map(data?.rolling.map((p) => [p.day, p.value]) ?? []);
  const chartData = (data?.pts ?? []).map((p) => ({ x: label(p), v: p.value, est: p.isEstimated, avg: rollByDay.get(p.day),
    err: p.min !== undefined && p.max !== undefined ? [p.value - p.min, p.max - p.value] : undefined }));
  const headline = range === 'D' && isSum ? data?.sum.total : data?.sum.average;

  return (
    <div>
      <h1 style={{ color }}>{m.displayName}</h1>
      <section className="panel">
        <div className="segmented" role="group" aria-label="Time range">
          {RANGES.map((r) => <button key={r} aria-pressed={range === r} onClick={() => setRange(r)}>{r}</button>)}
        </div>
        <div style={{ margin: '.75rem 0' }}>
          <div className="sub" style={{ textTransform: 'uppercase', fontWeight: 600 }}>{range === 'D' ? (isSum ? 'Total' : 'Average') : isSum ? 'Daily average' : 'Average'}</div>
          <div className="value" style={{ fontSize: '2rem', fontWeight: 700 }}>{fmtValue(headline, m)}</div>
          <div className="sub">{data ? (range === 'D' ? fmtDay(today) : `${fmtDay(data.from)} – ${fmtDay(today)}`) : ''}</div>
        </div>
        <div className="chart" role="img" aria-label={`${m.displayName} chart: ${chartData.length} values, average ${fmtValue(data?.sum.average, m)}`}>
          {!chartData.length ? <p className="muted">No data for this period.</p> : (
            <ResponsiveContainer>
              {bars ? (
                <ComposedChart data={chartData}>
                  <CartesianGrid strokeDasharray="3 3" vertical={false} stroke="var(--border)" />
                  <XAxis dataKey="x" tick={{ fontSize: 11 }} minTickGap={16} />
                  <YAxis tick={{ fontSize: 11 }} width={48} />
                  <Tooltip formatter={(v: number) => fmtValue(v, m)} />
                  <Bar isAnimationActive={false} dataKey="v" fill={color} radius={[3, 3, 0, 0]} name={m.displayName} />
                  {showAvg && data?.rolling.length ? <Line isAnimationActive={false} dataKey="avg" stroke="var(--blue)" strokeDasharray="4 3" dot={false} name="7-day average" /> : null}
                  {range !== 'D' && data?.sum.average !== undefined && <ReferenceLine y={data.sum.average} stroke="var(--muted)" strokeDasharray="2 3" />}
                </ComposedChart>
              ) : (
                <ComposedChart data={chartData}>
                  <CartesianGrid strokeDasharray="3 3" vertical={false} stroke="var(--border)" />
                  <XAxis dataKey="x" tick={{ fontSize: 11 }} minTickGap={16} />
                  <YAxis tick={{ fontSize: 11 }} width={48} domain={['auto', 'auto']} />
                  <Tooltip formatter={(v: number) => fmtValue(v, m)} />
                  <Scatter isAnimationActive={false} dataKey="v" fill={color} name={m.displayName}>
                    <ErrorBar dataKey="err" width={0} strokeWidth={5} stroke={color} opacity={0.3} direction="y" />
                  </Scatter>
                  {showAvg && data?.rolling.length ? <Line isAnimationActive={false} dataKey="avg" stroke="var(--blue)" strokeDasharray="4 3" dot={false} name="7-day average" /> : null}
                </ComposedChart>
              )}
            </ResponsiveContainer>
          )}
        </div>
        <ChartTable caption={`${m.displayName} values`} rows={chartData.map((d) => [d.x, fmtValue(d.v, m)])} />
        {(range === 'W' || range === 'M') && (
          <label style={{ display: 'flex', gap: 8, marginTop: 8 }}><input type="checkbox" checked={showAvg} onChange={(e) => setShowAvg(e.target.checked)} /> Show 7-day average</label>
        )}
        {data?.perDay && <p className="sub">Bars show the average per day in each period.</p>}
      </section>

      {data?.notes.length ? (
        <section className="panel"><h2 style={{ marginTop: 0 }}>Notable</h2>{data.notes.map((n) => <p key={n.id}>{findingText(n)}</p>)}</section>
      ) : null}

      {data && (data.week.current !== undefined) && (
        <section className="panel">
          <h2 style={{ marginTop: 0 }}>Compared with last period</h2>
          {[['This week vs last week', data.week], ['This month vs last month', data.month]].map(([t, c]) => {
            const cc = c as typeof data.week;
            const p = pctChange(cc), dir = direction(cc, m.higherIsBetter);
            return (
              <div className="row" key={t as string}>
                <span>{t as string}<br /><span className="sub">{cc.currentDays} vs {cc.previousDays} days with data</span></span>
                <span style={{ textAlign: 'right' }}>{fmtValue(cc.current, m)} vs {fmtValue(cc.previous, m)}<br />
                  {p !== undefined && <strong className={dir > 0 ? 'up' : dir < 0 ? 'down' : ''}>{p >= 0 ? '▲' : '▼'} {Math.abs(Math.round(p * 100))}%</strong>}</span>
              </div>
            );
          })}
        </section>
      )}

      {data?.bests.length ? (
        <section className="panel">
          <h2 style={{ marginTop: 0 }}>Personal bests</h2>
          {data.bests.map((b) => (
            <div className="row" key={b.period}><span>🏆 Best {b.period}</span><span>{fmtValue(b.value, m)} <span className="sub">{b.period === 'month' ? fmtDay(b.day, { month: 'long', year: 'numeric' }) : fmtDay(b.day, { month: 'short', day: 'numeric', year: 'numeric' })}</span></span></div>
          ))}
        </section>
      ) : null}
      <p className="sub">{m.kind === 'cumulative' ? 'Totals are deduplicated across devices using your source order (Settings). Apple Health applies its own order on iPhone, so totals may differ slightly.'
        : m.kind === 'discrete' ? 'Each day uses one source (your preferred one, or the device with the most readings).' : ''}</p>
    </div>
  );
}
