import { useApp } from './App';
import { useAsync } from './components';
import { patterns } from '../data/services';
import { findingText } from '../core/insights';

/** Stats-engine findings (no AI on the web — numbers and wording come from
 *  the same deterministic engine as iOS). */
export function PatternsView() {
  const { today, revision, settings } = useApp();
  const fs = useAsync(() => patterns(today, settings), [today, revision]);
  return (
    <div>
      <h1>Patterns</h1>
      <p className="muted">Statistical patterns in your last 90 days (false-discovery-rate controlled). They describe correlations in your data, not causes.</p>
      {!fs ? <p className="muted">Analysing…</p> : !fs.length ? <section className="panel">No clear patterns yet — they appear once there's enough data to be confident.</section> : (
        fs.map((f) => (
          <section className="panel" key={f.id}>
            <strong>{f.kind === 'anomaly' ? '⚠️ Unusual today' : f.kind === 'trendChange' ? '📈 Trend change' : '🔗 Pattern'}</strong>
            <p style={{ margin: '.4rem 0' }}>{findingText(f)}</p>
            <span className="sub">{f.kind === 'conditional' ? `${f.n} days · p = ${(f.pValue ?? 1).toFixed(3)}` : f.kind === 'correlation' ? `${f.n} days · Spearman` : f.kind === 'anomaly' ? `vs last ${f.n} days` : 'last 14 vs prior 28 days'}</span>
          </section>
        ))
      )}
      <p className="disclaimer">Not medical advice. If something worries you, talk to a healthcare professional.</p>
    </div>
  );
}
