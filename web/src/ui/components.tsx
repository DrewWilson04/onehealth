import { useEffect, useState } from 'react';
import type { MetricType } from '../core/model';
import { parseAttribution } from '../core/model';
import { inferVendor, VENDOR_NAME } from '../core/source';
import { href } from './router';
import { fmtValue, SECTION_COLOR, scoreColor } from './format';
import type { TrendPoint } from '../core/aggregate';
import type { ScoreResult } from '../core/scores';
import { scoreLabel } from '../core/scores';

export function useAsync<T>(fn: () => Promise<T>, deps: unknown[]): T | undefined {
  const [v, setV] = useState<T>();
  useEffect(() => {
    let alive = true;
    fn().then((x) => { if (alive) setV(x); });
    return () => { alive = false; };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, deps);
  return v;
}

export function SourceBadge({ attribution }: { attribution?: string }) {
  if (!attribution) return null;
  const s = parseAttribution(attribution);
  const v = inferVendor(s);
  const name = v === 'other' ? s.name || s.bundleId : VENDOR_NAME[v];
  return name ? <span className="sub" aria-label={`Source: ${name}`}>via {name}</span> : null;
}

export function Sparkline({ points, color, bars }: { points: TrendPoint[]; color: string; bars: boolean }) {
  if (points.length < 2) return null;
  const w = 140, h = 34, max = Math.max(...points.map((p) => p.value)), min = bars ? 0 : Math.min(...points.map((p) => p.value));
  const sx = (i: number) => (i / (points.length - 1)) * (w - 6) + 3;
  const sy = (v: number) => h - 2 - ((v - min) / Math.max(1e-9, max - min)) * (h - 4);
  return (
    <svg width="100%" height={h} viewBox={`0 0 ${w} ${h}`} aria-hidden preserveAspectRatio="none">
      {bars ? points.map((p, i) => <rect key={i} x={sx(i) - 4} y={sy(p.value)} width={8} height={h - sy(p.value)} rx={2} fill={color} opacity={p.isEstimated ? 0.35 : 0.85} />)
        : <polyline fill="none" stroke={color} strokeWidth={2} points={points.map((p, i) => `${sx(i)},${sy(p.value)}`).join(' ')} />}
    </svg>
  );
}

export function MetricCard({ m, value, sub, week, source, estimated }: { m: MetricType; value?: number; sub?: React.ReactNode; week: TrendPoint[]; source?: string; estimated?: boolean }) {
  const color = SECTION_COLOR[m.section];
  return (
    <a className="card" href={href('metric', m.id)} aria-label={`${m.displayName}, ${fmtValue(value, m)}`}>
      <div className="title" style={{ color }}>{m.displayName}</div>
      <div className="value">{fmtValue(value, m)}</div>
      <div className="sub">{sub ?? (value === undefined ? 'No data' : '')}</div>
      <Sparkline points={week} color={color} bars={m.kind === 'cumulative' || m.kind === 'workout'} />
      <div style={{ display: 'flex', gap: 6, alignItems: 'center' }}>
        <SourceBadge attribution={source} />
        {estimated && <span className="pill">Estimated</span>}
      </div>
    </a>
  );
}

export function Rings({ rings, size = 96 }: { rings: { label: string; progress: number; color: string }[]; size?: number }) {
  const sw = size / 9;
  return (
    <svg width={size} height={size} viewBox={`0 0 ${size} ${size}`} role="img"
      aria-label={rings.map((r) => `${r.label} ${Math.round(r.progress * 100)} percent`).join(', ')}>
      {rings.map((r, i) => {
        const rad = size / 2 - sw / 2 - i * (sw + 3);
        const c = 2 * Math.PI * rad;
        return (
          <g key={r.label} transform={`rotate(-90 ${size / 2} ${size / 2})`}>
            <circle cx={size / 2} cy={size / 2} r={rad} fill="none" stroke={r.color} strokeOpacity={0.18} strokeWidth={sw} />
            <circle cx={size / 2} cy={size / 2} r={rad} fill="none" stroke={r.color} strokeWidth={sw} strokeLinecap="round"
              strokeDasharray={`${Math.min(1, Math.max(0.001, r.progress)) * c} ${c}`} />
          </g>
        );
      })}
    </svg>
  );
}

export function ScoreCard({ r }: { r?: ScoreResult }) {
  if (!r) return <div className="card"><div className="title">…</div></div>;
  const title = { readiness: 'Readiness', sleep: 'Sleep Score', strain: 'Strain', energy: 'Energy' }[r.kind];
  return (
    <a className="card" href={href('score', r.kind)}>
      <div className="title" style={{ color: 'var(--green)' }}>{title}</div>
      {r.value !== undefined ? (
        <>
          <div className="value" style={{ color: r.kind === 'strain' ? 'var(--orange)' : scoreColor(r.value) }}>
            {r.kind === 'strain' ? r.value.toFixed(1) : Math.round(r.value)}<span className="sub"> / {r.kind === 'strain' ? 21 : 100}</span>
          </div>
          <div className="sub">{scoreLabel(r)}{r.kind === 'strain' && r.reason ? ` · ${r.reason}` : ''}</div>
          {r.isEstimated && <span className="pill">Estimated · {r.confidence}</span>}
        </>
      ) : (
        <><div className="value">—</div><div className="sub">{r.reason ?? 'Not enough data'}</div></>
      )}
    </a>
  );
}

/** Visually hidden data table so screen-reader users get every chart value. */
export function ChartTable({ caption, rows }: { caption: string; rows: [string, string][] }) {
  return (
    <table className="sr-only">
      <caption>{caption}</caption>
      <thead><tr><th>Date</th><th>Value</th></tr></thead>
      <tbody>{rows.map(([a, b]) => <tr key={a}><td>{a}</td><td>{b}</td></tr>)}</tbody>
    </table>
  );
}
