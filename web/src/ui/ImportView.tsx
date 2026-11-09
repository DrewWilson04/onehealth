import { useRef, useState } from 'react';
import { useApp } from './App';
import type { FromWorker, ToWorker } from '../worker/protocol';
import type { Progress } from '../worker/importer';
import { BRAND } from '../brand';
import { href } from './router';

export function ImportView() {
  const app = useApp();
  const [over, setOver] = useState(false);
  const [progress, setProgress] = useState<Progress>();
  const [error, setError] = useState<string>();
  const [running, setRunning] = useState(false);
  const worker = useRef<Worker>();
  const started = useRef(0);

  const start = (file: File) => {
    setError(undefined);
    setRunning(true);
    app.setLastFile(file);
    started.current = Date.now();
    const w = new Worker(new URL('../worker/importWorker.ts', import.meta.url), { type: 'module' });
    worker.current = w;
    w.onmessage = async (e: MessageEvent<FromWorker>) => {
      const m = e.data;
      if (m.kind === 'progress') setProgress(m.progress);
      if (m.kind === 'error') { setError(m.message); setRunning(false); w.terminate(); }
      if (m.kind === 'done') { setRunning(false); w.terminate(); await app.reload(); location.hash = href('dashboard'); }
    };
    w.postMessage({ kind: 'import', file, priority: app.settings.priority, preferred: app.settings.preferred } satisfies ToWorker);
  };
  const cancel = () => { worker.current?.postMessage({ kind: 'cancel' } satisfies ToWorker); };

  const pct = progress && progress.totalBytes ? Math.min(1, progress.bytes / progress.totalBytes) : undefined;
  const eta = pct && pct > 0.02 ? ((Date.now() - started.current) / pct) * (1 - pct) / 1000 : undefined;

  return (
    <div>
      <h1>Import your Apple Health data</h1>
      <section className="panel">
        <ol>
          <li>On your iPhone, open <strong>Health</strong> → tap your profile picture → <strong>Export All Health Data</strong>.</li>
          <li>Save or AirDrop the <code>export.zip</code> to this computer (it can be several GB — that's fine).</li>
          <li>Drop it below. Everything is processed <strong>locally in your browser</strong>; nothing is uploaded.</li>
        </ol>
      </section>
      <div
        className={`dropzone ${over ? 'over' : ''}`}
        onDragOver={(e) => { e.preventDefault(); setOver(true); }}
        onDragLeave={() => setOver(false)}
        onDrop={(e) => { e.preventDefault(); setOver(false); const f = e.dataTransfer.files[0]; if (f && !running) start(f); }}
      >
        {!running ? (
          <>
            <p><strong>Drop export.zip here</strong> or</p>
            <label>
              <input type="file" accept=".zip,.xml,application/zip,text/xml" className="sr-only" onChange={(e) => e.target.files?.[0] && start(e.target.files[0])} />
              <span className="primary" style={{ display: 'inline-block', padding: '.5rem 1rem', borderRadius: 10, background: 'var(--blue)', color: '#fff', cursor: 'pointer' }}>Choose file…</span>
            </label>
            <p className="muted" style={{ marginTop: '1rem' }}>Accepts export.zip or an extracted export.xml.</p>
          </>
        ) : (
          <div aria-live="polite">
            <p><strong>{progress?.phase === 'aggregating' ? `Building summaries${progress.detail ? ` — ${progress.detail}` : ''}…` : 'Reading your export…'}</strong></p>
            <progress value={pct ?? undefined} max={1} aria-label="Import progress" />
            <p className="muted">{progress?.records.toLocaleString() ?? 0} records{pct !== undefined ? ` · ${Math.round(pct * 100)}%` : ''}{eta ? ` · about ${Math.ceil(eta)} s left` : ''}</p>
            <button onClick={cancel}>Cancel</button>
          </div>
        )}
      </div>
      {error && <div className="banner info" role="alert"><strong>Import failed:</strong> {error}</div>}
      {app.info && !running && <p className="muted">Importing again replaces the current snapshot.</p>}
      <p className="muted">{BRAND.name} on the web shows an imported snapshot. For live data, scores that update through the day, logging and widgets, use the iPhone app.</p>
    </div>
  );
}
