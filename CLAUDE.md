# confessional-christianity-v2: facts

## What it is
confessionalchristianity.com (Next.js 16, App Router, on Vercel) and the **Confessional Christianity** iOS app (SwiftUI,
live on the App Store: 1.0 READY_FOR_SALE, build 2, Aug 2026). Catechizing a child through a historic catechism, plus
the confessions and scripture. Devotions, reading plans, Family Worship, the prayer list and the web
catechism session (`/programs`) were cut in TKL-856; their old URLs 301 in `next.config.ts`. Background: `README.md`, `docs/DOMAIN.md` (id grammar; read
before touching search or routing), `docs/catechism-first-prd.md`.
Linear project: **confessional christianity** (team TKL): https://linear.app/software-studio/project/confessional-christianity-737c8c0f61f0

## Layout
- `src/`: the website (App Router). `content/`: essays, program prayers (markdown/JSON, source of truth).
- `normalized-data/`, `dataMapping/`: confession text and the id → entry map (server-only).
- `supabase/migrations/`: the account schema (live Supabase project shared with v1).
- `scripts/`: Algolia indexing, prayers authoring, `ios/sync-content.mjs` (copies `content/` into the app bundle).
- `ios/App/`: the app. `project.yml` is the XcodeGen spec (the `.xcodeproj` is generated; don't hand-edit it). `Sources/`, `Widget/` (Home Screen widget, App Group `group.com.confessionalchristianity.app`).
- `ios/DomainKit/`: SwiftPM package with the app's pure logic and bundled content; its tests run on the host Mac.
  `QuoteCard/` is the share-image renderer (TKL-842), with its own copy of the fonts in `QuoteCardFonts/`. Its snapshot
  fixtures are in `Tests/DomainKitTests/Fixtures/QuoteCard/`: re-record `native/` with `QUOTE_CARD_RECORD=1 swift test`
  after an intended visual change; regenerate `prototype/` (the approved TKL-840 design via headless Chrome) with
  `ios/DomainKit/scripts/quote-card-prototype/render.sh`.
- `ios/AppStoreScreenshots/`, `ios/design-assets/`: listing art.

## Setup
- Node 22, `npm ci`.
- Each worktree needs the gitignored `.env.local`: copy it from the main checkout (`cp ../confessional-christianity-v2/.env.local .`). Names are in `.env.example`; never print values.
- Xcode 27, XcodeGen at `/opt/homebrew/bin/xcodegen`. Bundle id `com.confessionalchristianity.app`, team `7GZKY29XJH`, automatic signing. iOS 17.0 target, Swift 6.
- Simulator: **"CC iPhone 17 Pro"** (its own, so runs don't fight barbrabell's shared "iPhone 17 Pro").

## Test (from the repo root)
| Suite | Command | Runtime |
|---|---|---|
| web unit | `npm test` (vitest, 114 tests) | ~1 s |
| web build | `npm run build` (needs `.env.local`; ESLint enforced) | ~15 s |
| DomainKit | `cd ios/DomainKit && swift test` (135 tests) | ~15 s |
| iOS build | `cd ios/App && xcodegen generate && xcodebuild -scheme ConfessionalChristianity -destination 'platform=iOS Simulator,name=CC iPhone 17 Pro' -derivedDataPath ../../build/dd build` | ~1 min cold |
| DB (pgTAP) | see "DB tests" below (local Supabase in Docker, 35 tests) | ~40 s |

### DB tests (pgTAP, local stack only)
`supabase/config.toml` runs a local stack on ports 5542x (container `supabase_db_confessional-christianity`). Docker must be running.
```sh
supabase start -x studio,imgproxy,storage-api,realtime,edge-runtime,logflare,vector,supavisor,mailpit,postgres-meta
supabase db reset        # local container only: never add --linked or --db-url
out=$(for f in supabase/tests/*.test.sql; do
  docker exec -i supabase_db_confessional-christianity psql -U postgres -q -tA -v ON_ERROR_STOP=1 < "$f" \
    || echo "not ok - psql failed on $f"; done)
echo "$out" | grep -c '^ok'                           # 35 today
! echo "$out" | grep -E '^not ok|Looks like' && echo PASS
supabase stop            # when done
```
Pass = `PASS` printed (no `not ok`, no pgTAP plan mismatch, no SQL error). Don't use `supabase test db` unattended: with
CLI v2.39.2 it hung >5 min twice after `create extension pgtap` (pulling the pg_prove image, TKL-809). Run the DB tests when
a change touches `supabase/`.

## Verify checks
A change lands only with these green: `npm test`, `npm run build`, `swift test` in `ios/DomainKit`, and the iOS build.
A change under `supabase/` also needs the DB tests (pgTAP, above) printing `PASS`.
A UI change also gets a simulator screenshot (iOS) or a browser screenshot (web).

## Land
Fast-forward to `origin/main` (no PRs): branch a worktree from `origin/main`, commit, `git push origin HEAD:main`.
Never commit in the main checkout: it often holds Maxwell's uncommitted work on another branch.

## Deploy
- **Web:** Vercel serves https://confessionalchristianity.com (`server: Vercel`). Whether a push to `main` deploys by itself is unverified; check the Vercel project before relying on it. Post-deploy: `/`, `/library`, `/search` return 200.
- **iOS:** no release script yet. Bump `CURRENT_PROJECT_VERSION` (and `MARKETING_VERSION` for a new App Store version) in `ios/App/project.yml`, archive and upload with Xcode (`xcodebuild archive` + `-exportArchive`, `-allowProvisioningUpdates`). **Signing blocks this today (TKL-880):** `archive` succeeds, but `-exportArchive` fails — team 7GZKY29XJH has no Apple Distribution certificate (`GET /v1/certificates` shows only DEVELOPMENT and DEVELOPER_ID_APPLICATION), this Mac has only an `Apple Development` identity, and the ASC API key lacks cloud-managed distribution signing, so `-allowProvisioningUpdates` cannot create one. Don't spend an archive discovering this: check `security find-identity -v -p codesigning` for an `Apple Distribution` identity first. App Store Connect API key: `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_PATH` in `~/dev/.secrets.env` (same team as barbrabell). Versions stay on manual release.
- **iOS build numbers so far** (App Store Connect, checked 2026-11-19): pre-release version string is `0.1.0`, builds **1** and **2**
  (both uploaded Aug 2026, both now expired in TestFlight). The App Store *version record* is `1.0` READY_FOR_SALE and points at
  build 2, so the store version string and the build's version string differ — don't infer the next build number from the store
  version. Next build number is one above the highest ever uploaded, expired or not; query
  `/v1/builds?filter[app]=6797692942` (app id) rather than the builds list on the app, which hides expired builds.
- Internal TestFlight group: **"updates"** (`isInternalGroup: true`). Assign each uploaded build to it or no one can install.
- Content changes (`content/`) reach the app only through `npm run ios:sync-content` and a new build (TKL-683 would decouple that).

## Gotchas
- Supabase migrations touch live user data: review required. **Never run migrations against the live project** (no
  `supabase db push`, `--linked`, or `--db-url` to prod); test them only on the local stack. Applying to prod is Maxwell's.
- The Algolia Admin key is for `scripts/` only; the browser gets the search-only key.
