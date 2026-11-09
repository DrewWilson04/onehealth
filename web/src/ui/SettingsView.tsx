import { useState } from 'react';
import { useApp } from './App';
import { metric, METRICS, sourceKey, type SourceRef } from '../core/model';
import { inferVendor, VENDOR_NAME, SourcePriority } from '../core/source';
import { deleteEverything } from '../db/db';
import { aggregates, samples as getSamples } from '../db/queries';
import { dailySummaryCSV, samplesCSV } from '../core/csv';
import { addDays, dayStartMs, LOCAL } from '../core/daykey';
import type { Goal } from '../core/aggregate';
import type { DailyAggregate } from '../core/model';
import { BRAND } from '../brand';

function download(name: string, text: string) {
  const url = URL.createObjectURL(new Blob([text], { type: 'text/csv;charset=utf-8' }));
  const a = Object.assign(document.createElement('a'), { href: url, download: name });
  a.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}

export function SettingsView() {
  const app = useApp();
  const { settings, info, today } = app;
  const allSources = new Map<string, SourceRef>();
  for (const list of Object.values(info?.sources ?? {})) for (const s of list) allSources.set(sourceKey(s), s);
  const p = new SourcePriority(settings.priority);
  const ordered = [...allSources.values()].sort((a, b) => (p.isHigher(a, undefined, b, undefined) ? -1 : 1));
  const [from, setFrom] = useState(addDays(today, -29));
  const [to, setTo] = useState(today);
  const [dirty, setDirty] = useState(false);

  const move = async (i: number, d: number) => {
    const keys = ordered.map(sourceKey);
    const [k] = keys.splice(i, 1);
    keys.splice(i + d, 0, k);
    await app.updateSettings({ ...settings, priority: keys });
    setDirty(true);
  };
  const setGoal = (g: Goal, target: number) => app.updateSettings({ ...settings, goals: settings.goals.map((x) => (x.id === g.id ? { ...x, target } : x)) });

  const exportDaily = async () => {
    const rows = new Map<string, DailyAggregate[]>();
    const ms = METRICS.filter((m) => m.kind !== 'ecg');
    const withData = [];
    for (const m of ms) { const r = await aggregates(m.id, 'day', from, to); if (r.length) { rows.set(m.id, r); withData.push(m); } }
    download(`${BRAND.name}-daily-${from}_to_${to}.csv`, dailySummaryCSV(withData, rows, from, to));
  };
  const exportSamples = async () => {
    const all = [];
    for (const m of METRICS.filter((x) => !x.isHighVolume)) all.push(...await getSamples(m.id, dayStartMs(from, LOCAL), dayStartMs(addDays(to, 1), LOCAL)));
    download(`${BRAND.name}-samples-${from}_to_${to}.csv`, samplesCSV(all));
  };

  return (
    <div>
      <h1>Settings</h1>
      {info && (
        <section className="panel">
          <h2 style={{ marginTop: 0 }}>Imported snapshot</h2>
          <div className="row"><span>File</span><span>{info.fileName}</span></div>
          <div className="row"><span>Records</span><span>{info.counts.records.toLocaleString()} ({info.counts.skipped.toLocaleString()} skipped)</span></div>
          <div className="row"><span>Range</span><span>{info.firstDay} – {info.lastDay}</span></div>
          <div className="row"><span>Time zone used</span><span>{info.timeZone}</span></div>
        </section>
      )}
      <section className="panel">
        <h2 style={{ marginTop: 0 }}>Source priority</h2>
        <p className="sub">Apple Health's export has no source order, so {BRAND.name} uses this list when devices overlap (default: Apple Watch, then wearables, then iPhone, then apps).</p>
        {ordered.map((s, i) => (
          <div className="row" key={sourceKey(s)}>
            <span>{i + 1}. {s.name} <span className="sub">{VENDOR_NAME[inferVendor(s)]}</span></span>
            <span><button aria-label={`Move ${s.name} up`} disabled={i === 0} onClick={() => move(i, -1)}>↑</button> <button aria-label={`Move ${s.name} down`} disabled={i === ordered.length - 1} onClick={() => move(i, 1)}>↓</button></span>
          </div>
        ))}
        {dirty && app.lastFile && <p><button className="primary" onClick={() => { location.hash = '#/import'; }}>Re-import to apply</button></p>}
        {dirty && !app.lastFile && <p className="sub">Re-import your export to apply the new order.</p>}
      </section>
      <section className="panel">
        <h2 style={{ marginTop: 0 }}>Goals</h2>
        {settings.goals.map((g) => (
          <div className="row" key={g.id}>
            <label htmlFor={`goal-${g.id}`}>{metric(g.metric)?.displayName}</label>
            <input id={`goal-${g.id}`} type="number" value={g.target} min={0} onChange={(e) => setGoal(g, Number(e.target.value))} style={{ width: 110 }} />
          </div>
        ))}
      </section>
      <section className="panel">
        <h2 style={{ marginTop: 0 }}>Export CSV</h2>
        <div className="row"><label>From <input type="date" value={from} onChange={(e) => setFrom(e.target.value)} /></label><label>To <input type="date" value={to} onChange={(e) => setTo(e.target.value)} /></label></div>
        <p><button onClick={exportDaily}>Daily summary CSV</button> <button onClick={exportSamples}>Raw samples CSV</button></p>
        <p className="sub">Files are generated in your browser.</p>
      </section>
      <section className="panel">
        <h2 style={{ marginTop: 0 }}>Your data</h2>
        <p className="sub">Everything is stored only in this browser (IndexedDB). Nothing was uploaded.</p>
        <button onClick={async () => { if (confirm('Delete all imported data from this browser?')) { await deleteEverything(); location.hash = '#/import'; location.reload(); } }}>Delete all data</button>
      </section>
    </div>
  );
}
