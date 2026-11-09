import { createContext, useCallback, useContext, useEffect, useState } from 'react';
import { BRAND } from '../brand';
import { useRoute, href } from './router';
import { loadImportInfo, loadSettings, saveSettings, snapshotDay, type Settings } from '../data/services';
import type { ImportInfo } from '../db/queries';
import { ImportView } from './ImportView';
import { Dashboard } from './Dashboard';
import { MetricDetail } from './MetricDetail';
import { SectionView } from './SectionView';
import { SleepView } from './SleepView';
import { WorkoutsView } from './WorkoutsView';
import { ScoreDetail } from './ScoreDetail';
import { PatternsView } from './PatternsView';
import { SettingsView } from './SettingsView';
import type { ScoreKind } from '../core/scores';
import { fmtDay } from './format';

interface AppState {
  info?: ImportInfo;
  settings: Settings;
  today: string;
  revision: number;
  reload: () => Promise<void>;
  updateSettings: (s: Settings) => Promise<void>;
  lastFile?: File;
  setLastFile: (f: File) => void;
}
const Ctx = createContext<AppState | null>(null);
export const useApp = () => useContext(Ctx)!;

export function App() {
  const [info, setInfo] = useState<ImportInfo>();
  const [settings, setSettings] = useState<Settings>({ priority: [], preferred: {}, goals: [], sleepGoalMinutes: 480 });
  const [revision, setRevision] = useState(0);
  const [loaded, setLoaded] = useState(false);
  const [lastFile, setLastFile] = useState<File>();
  const route = useRoute();

  const reload = useCallback(async () => {
    setInfo(await loadImportInfo());
    setSettings(await loadSettings());
    setRevision((r) => r + 1);
    setLoaded(true);
  }, []);
  useEffect(() => { void reload(); }, [reload]);

  const updateSettings = async (s: Settings) => { await saveSettings(s); setSettings(s); setRevision((r) => r + 1); };
  const state: AppState = { info, settings, today: snapshotDay(info), revision, reload, updateSettings, lastFile, setLastFile };
  const page = !info && route[0] !== 'privacy' && route[0] !== 'settings' ? 'import' : route[0];

  const tabs: [string, string][] = [['dashboard', 'Today'], ['section/activity', 'Activity'], ['section/sleep', 'Sleep'], ['section/heart', 'Heart'], ['section/body', 'Body'], ['patterns', 'Patterns'], ['import', 'Import'], ['settings', 'Settings']];

  return (
    <Ctx.Provider value={state}>
      <header className="top">
        <a className="brand" href={href('dashboard')}><img src="./icon.svg" alt="" width={26} height={26} />{BRAND.name}</a>
        {info && (
          <nav className="tabs" aria-label="Main">
            {tabs.map(([path, label]) => (
              <a key={path} href={'#/' + path} aria-current={route.join('/') === path || (path === 'dashboard' && route[0] === 'dashboard') ? 'page' : undefined}>{label}</a>
            ))}
          </nav>
        )}
      </header>
      <main>
        {info && page !== 'import' && (
          <div className="banner snapshot" role="status">
            <span aria-hidden>📸</span>
            <span><strong>Imported snapshot from {fmtDay(state.today, { month: 'long', day: 'numeric', year: 'numeric' })}</strong> — not live data.
              Re-import a new export to update. Your data stays in this browser.</span>
          </div>
        )}
        {!loaded ? <p className="muted">Loading…</p> : <Page route={page === 'import' ? ['import'] : route} />}
        <p className="disclaimer">{BRAND.name} is not a medical device and does not provide medical advice. Scores are our own estimates, not equivalent to WHOOP, Garmin or Oura scores. <a href={href('privacy')}>Privacy</a></p>
      </main>
    </Ctx.Provider>
  );
}

function Page({ route }: { route: string[] }) {
  switch (route[0]) {
    case 'import': return <ImportView />;
    case 'metric': return <MetricDetail id={route[1]} />;
    case 'section': return <SectionView id={route[1]} />;
    case 'sleep': return <SleepView />;
    case 'workouts': return <WorkoutsView />;
    case 'score': return <ScoreDetail kind={route[1] as ScoreKind} />;
    case 'patterns': return <PatternsView />;
    case 'settings': return <SettingsView />;
    case 'privacy': return <section className="panel"><iframe title="Privacy policy" src="./privacy.html" style={{ width: '100%', height: '70vh', border: 0 }} /></section>;
    default: return <Dashboard />;
  }
}
