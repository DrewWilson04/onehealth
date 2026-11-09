# PulseBoard — web companion

A static PWA that imports an Apple Health `export.zip` **entirely in your browser**. Nothing is uploaded: there is no server, analytics or third-party network call, and the production build ships with a strict CSP (`connect-src 'self'`).

It shows the same dashboard, trends and derived scores as iOS, computed by TypeScript ports of PulseCore. The ports are tested against the shared fixtures in `/docs/fixtures`.

The UI clearly states that this is an **imported snapshot, not live data**. There's no subscription gating on the web.

## Run locally
```sh
cd web
npm ci
npm run dev        # http://localhost:5173
npm test           # 67 tests: core parity with iOS fixtures, ZIP/ZIP64, streaming importer, memory bound
npm run build      # → web/dist (static files)
npm run preview    # serve the production build
```

**Sample data.** `node scripts/make-sample-export.mjs sample.zip 75` generates a synthetic 75-day export with multiple overlapping devices (Apple Watch, iPhone, Oura, Withings).

## How the import works (bounded memory, 1 GB+ exports)
1. **Read the ZIP central directory.** `src/worker/zip.ts` uses `Blob.slice` for random access and supports ZIP64. It finds `export.xml` and counts ECG files.
2. **Decompress as a stream.** The entry streams through the native `DecompressionStream('deflate-raw')`, then a streaming SAX parser (`saxes`), all inside a **Web Worker**.
3. **Normalize records.** Each record goes through the same rules as iOS (`src/core/normalize.ts`), which give identical stable ids.
4. **Store low-volume types raw** in IndexedDB, in batches of 5,000: sleep, workouts, HRV, resting HR, body, nutrition and vitals.
5. **Never store high-volume types raw.** Steps, energy, distance, heart rate and audio stream into small per-source hourly accumulators instead. For the last 120 days, per-minute HR and 15-minute step arrays are also kept for Strain and Energy.
   - Memory does not grow with file size. The test suite imports a 144 MB synthetic export (800k records) and checks the retained heap.
6. **Build aggregates** for hour, day, week, month and year. These power the charts.

**Dedup on the web.** `export.xml` has no Apple Health source priority, so the web uses its own order, which you can edit in Settings:
- **Cumulative types:** higher-priority sources claim their covered share of each hour first.
- **Discrete types:** one source per day.

Totals can differ slightly from the Health app.

## Deploy (free static hosting)
The build uses a relative `base`, so it works at any path.

### Cloudflare Pages
1. Go to dash.cloudflare.com → Workers & Pages → Create → Pages → Connect to Git → choose this repo.
2. Use these build settings:
   - **Root directory:** `web`
   - **Build command:** `npm ci && npm run build`
   - **Build output directory:** `dist`
   - **Environment variable:** `NODE_VERSION=22`
3. Deploy. Every push redeploys.

### GitHub Pages
The workflow `.github/workflows/web.yml` tests, builds and deploys `web/dist` on pushes to `main` that touch `web/**` or `docs/fixtures/**`.
1. Go to Repo → Settings → Pages → **Source: GitHub Actions**.
2. Push to `main`, or run the workflow manually. The site appears at `https://<user>.github.io/<repo>/`.

### Privacy policy URL
`/privacy.html` is a placeholder policy. Its URL can serve as `PRIVACY_POLICY_URL` for the iOS app and App Store Connect, after you review the text.

## Browser support
You need a recent browser with `DecompressionStream('deflate-raw')`, module Web Workers and IndexedDB:
- Chrome / Edge 80+
- Safari 16.4+
- Firefox 113+
