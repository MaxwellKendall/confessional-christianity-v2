# confessional-christianity-v2: facts

## What it is
confessionalchristianity.com (Next.js 16, App Router, on Vercel) and the **Confessional Christianity** iOS app (SwiftUI,
live on the App Store: 1.0 READY_FOR_SALE, build 2, Aug 2026). Catechizing a child through a historic catechism, plus
the confessions, scripture, devotions and reading plans. Background: `README.md`, `docs/DOMAIN.md` (id grammar; read
before touching search or routing), `docs/catechism-first-prd.md`.
Linear project: **confessional christianity** (team TKL): https://linear.app/software-studio/project/confessional-christianity-737c8c0f61f0

## Layout
- `src/`: the website (App Router). `content/`: essays, devotions, program prayers (markdown/JSON, source of truth).
- `normalized-data/`, `dataMapping/`: confession text and the id → entry map (server-only).
- `supabase/migrations/`: the account schema (live Supabase project shared with v1).
- `scripts/`: Algolia indexing, prayers/devotions authoring, `ios/sync-content.mjs` (copies `content/` into the app bundle).
- `ios/App/`: the app. `project.yml` is the XcodeGen spec (the `.xcodeproj` is generated; don't hand-edit it). `Sources/`, `Widget/` (Home Screen widget, App Group `group.com.confessionalchristianity.app`).
- `ios/DomainKit/`: SwiftPM package with the app's pure logic and bundled content; its tests run on the host Mac.
- `ios/AppStoreScreenshots/`, `ios/design-assets/`: listing art.

## Setup
- Node 22, `npm install` (not `npm ci`: `package-lock.json` on `main` is out of sync with `package.json`, see Linear).
- Each worktree needs the gitignored `.env.local`: copy it from the main checkout (`cp ../confessional-christianity-v2/.env.local .`). Names are in `.env.example`; never print values.
- Xcode 27, XcodeGen at `/opt/homebrew/bin/xcodegen`. Bundle id `com.confessionalchristianity.app`, team `7GZKY29XJH`, automatic signing. iOS 17.0 target, Swift 6.
- Simulator: **"CC iPhone 17 Pro"** (its own, so runs don't fight barbrabell's shared "iPhone 17 Pro").

## Test (from the repo root)
| Suite | Command | Runtime |
|---|---|---|
| web unit | `npm test` (vitest, 148 tests) | ~1 s |
| web build | `npm run build` (needs `.env.local`; ESLint enforced) | ~15 s |
| DomainKit | `cd ios/DomainKit && swift test` (98 tests) | ~15 s |
| iOS build | `cd ios/App && xcodegen generate && xcodebuild -scheme ConfessionalChristianity -destination 'platform=iOS Simulator,name=CC iPhone 17 Pro' -derivedDataPath ../../build/dd build` | ~1 min cold |

## Verify checks
A change lands only with these green: `npm test`, `npm run build`, `swift test` in `ios/DomainKit`, and the iOS build.
A UI change also gets a simulator screenshot (iOS) or a browser screenshot (web).

## Land
Fast-forward to `origin/main` (no PRs): branch a worktree from `origin/main`, commit, `git push origin HEAD:main`.
Never commit in the main checkout: it often holds Maxwell's uncommitted work on another branch.

## Deploy
- **Web:** Vercel serves https://confessionalchristianity.com (`server: Vercel`). Whether a push to `main` deploys by itself is unverified; check the Vercel project before relying on it. Post-deploy: `/`, `/library`, `/search` return 200.
- **iOS:** no release script yet. Bump `CURRENT_PROJECT_VERSION` (and `MARKETING_VERSION` for a new App Store version) in `ios/App/project.yml`, archive and upload with Xcode (`xcodebuild archive` + `-exportArchive`, `-allowProvisioningUpdates`, signed by the Xcode account on this Mac). App Store Connect API key: `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_PATH` in `~/dev/.secrets.env` (same team as barbrabell). Versions stay on manual release.
- Content changes (`content/`) reach the app only through `npm run ios:sync-content` and a new build (TKL-683 would decouple that).

## Gotchas
- Supabase migrations touch live user data: review required, never run against prod without Maxwell.
- The Algolia Admin key is for `scripts/` only; the browser gets the search-only key.
