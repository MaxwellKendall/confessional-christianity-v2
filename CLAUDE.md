# confessional-christianity-v2: facts

## What it is
confessionalchristianity.com (Next.js 16, App Router, on Vercel) and the **Confessional Christianity** iOS app (SwiftUI,
live on the App Store: 1.0 READY_FOR_SALE, build 2, Aug 2026). Its two pillars are catechizing children through a historic catechism and reflecting on Lord's Day sermon insights through weekly meditation. It also provides the confessions and scripture. Devotions, reading plans, Family Worship, the prayer list and the web
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
- `infra/`: AWS CDK (TypeScript) for accounts, the Cognito pools (see "Accounts" below and `infra/README.md`).
  `ios/App/Resources/amplify_outputs.{dev,prod}.json` are its generated, committed client configs.

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
| DomainKit | `cd ios/DomainKit && swift test` (152 tests) | ~15 s |
| iOS build | `cd ios/App && xcodegen generate && xcodebuild -scheme ConfessionalChristianity -destination 'platform=iOS Simulator,name=CC iPhone 17 Pro' -derivedDataPath ../../build/dd build` | ~1 min cold |
| infra | `cd infra && npm ci && npm test` (vitest CDK assertions, 12 tests) | ~6 s |
| DB (pgTAP) | see "DB tests" below (local Supabase in Docker, 22 tests) | ~40 s |

### DB tests (pgTAP, local stack only)
`supabase/config.toml` runs a local stack on ports 5542x (container `supabase_db_confessional-christianity`). Docker must be running.
```sh
supabase start -x studio,imgproxy,storage-api,realtime,edge-runtime,logflare,vector,supavisor,mailpit,postgres-meta
supabase db reset        # local container only: never add --linked or --db-url
out=$(for f in supabase/tests/*.test.sql; do
  docker exec -i supabase_db_confessional-christianity psql -U postgres -q -tA -v ON_ERROR_STOP=1 < "$f" \
    || echo "not ok - psql failed on $f"; done)
echo "$out" | grep -c '^ok'                           # 22 today
! echo "$out" | grep -E '^not ok|Looks like' && echo PASS
supabase stop            # when done
```
Pass = `PASS` printed (no `not ok`, no pgTAP plan mismatch, no SQL error). Don't use `supabase test db` unattended: with
CLI v2.39.2 it hung >5 min twice after `create extension pgtap` (pulling the pg_prove image, TKL-809). Run the DB tests when
a change touches `supabase/`.

## Verify checks
A change lands only with these green: `npm test`, `npm run build`, `swift test` in `ios/DomainKit`, and the iOS build.
A change under `supabase/` also needs the DB tests (pgTAP, above) printing `PASS`.
A change under `infra/` also needs `cd infra && npm test`.
A UI change also gets a simulator screenshot (iOS) or a browser screenshot (web).

## Land
Fast-forward to `origin/main` (no PRs): branch a worktree from `origin/main`, commit, `git push origin HEAD:main`.
Never commit in the main checkout: it often holds Maxwell's uncommitted work on another branch.

## Deploy
- **Web:** Vercel serves https://confessionalchristianity.com (`server: Vercel`). Whether a push to `main` deploys by itself is unverified; check the Vercel project before relying on it. Post-deploy: `/`, `/library`, `/search` return 200.
- **iOS:** no release script yet. Bump `CURRENT_PROJECT_VERSION` (and `MARKETING_VERSION` for a new App Store version) in `ios/App/project.yml`, archive and upload with Xcode (`xcodebuild archive` + `-exportArchive`, `-allowProvisioningUpdates`). **Signing (TKL-880, fixed 2026-11-20):** distribution signing is cloud-managed and works only through the Xcode account signed in on this Mac: plain `xcodebuild -exportArchive -allowProvisioningUpdates` (method `app-store-connect`, destination `upload`) signs with `Apple Distribution` and uploads. Passing the ASC API key (`-authenticationKey*`) to `-exportArchive` fails ("not given access to cloud-managed distribution certificates"), so don't; there is still no local `Apple Distribution` identity. App Store Connect API key: `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_PATH` in `~/dev/.secrets.env` (same team as barbrabell). Versions stay on manual release.
- **iOS build numbers so far** (App Store Connect, checked 2026-11-20): builds **1** and **2** were version `0.1.0` (Aug 2026, expired);
  build **3** is version `1.1` (uploaded 2026-11-20). The `0.1.0` train is closed (a `0.1.0` build was approved), so uploads need a
  `MARKETING_VERSION` above it. The App Store *version record* is `1.0` READY_FOR_SALE and points at build 2, so don't infer the next
  build number from the store version. Next build number is one above the highest ever uploaded, expired or not; query
  `/v1/builds?filter[app]=6797692942` (app id) rather than the builds list on the app, which hides expired builds.
- Internal TestFlight group: **"updates"** (`isInternalGroup: true`, `hasAccessToAllBuilds: true`, so new builds reach it once processed). A tester stays `NOT_INVITED` and gets no email while no build is valid; once one is, send the invite with `POST /v1/betaTesterInvitations`.
- Content changes (`content/`) reach the app only through `npm run ios:sync-content` and a new build (TKL-683 would decouple that).

## Accounts (`infra/`)
Cognito user pools, sign-in by a code emailed to the person (`USER_AUTH` + `EMAIL_OTP`; codes are 8 digits, sign-up
codes 6). CDK app in `infra/`, account `397614038040`, profile `aicoach-dev`, us-east-1. Four stacks:
`ConfessionalChristianityMail-{dev,prod}` (the SES sending domain) and `ConfessionalChristianity-{dev,prod}` (pool + public
iOS client). Stage from `-c stage=…` (default dev). Nothing is created in the console. Details: `infra/README.md`.
- From `infra/` on a worktree of `origin/main`: `npm test`, then `npx cdk diff --all --profile aicoach-dev -c stage=prod`,
  read it, then `npx cdk deploy --all --profile aicoach-dev -c stage=prod` (dev: drop `-c stage=prod`).
- **Stop** if the diff replaces or removes the user pool, its app client or the prod SES identity: the prod pool is `RETAIN`
  with deletion protection, and replacing it loses every account.
- A new mail domain must show `SUCCESS` in `aws sesv2 get-email-identity` before its pool stack deploys.
- After a deploy: `AWS_PROFILE=aicoach-dev npm run outputs [dev|prod]` rewrites `ios/App/Resources/amplify_outputs.{stage}.json`
  (commit it) and prints `COGNITO_USER_POOL_ID` / `COGNITO_CLIENT_ID` for the server. The IDs aren't secrets.
- Dev: pool `us-east-1_Tbhzx2V7a`, client `1qibu96101fa0n6iaiuqmpklq1`, mail from `cc-dev-mail.barbrabell.com`. Codes sent to
  `otp-test@cc-dev-mail.barbrabell.com` land in S3: `AWS_PROFILE=aicoach-dev infra/scripts/inbox-code.sh <since-epoch>` prints
  the newest. Never send codes to made-up outside addresses (bounces hurt the sender); SES is still in the sandbox.
- Prod: sends from `confessionalchristianity.com`, whose DNS is on Vercel (not reachable by agents). Its DKIM records are the
  `DkimRecords` output of `ConfessionalChristianityMail-prod`; the prod pool can't deploy until they verify.
- The Supabase account code in `supabase/` and the app is being replaced (TKL-812, TKL-890).

## Gotchas
- Supabase migrations touch live user data: review required. **Never run migrations against the live project** (no
  `supabase db push`, `--linked`, or `--db-url` to prod); test them only on the local stack. Applying to prod is Maxwell's.
- The Algolia Admin key is for `scripts/` only; the browser gets the search-only key.
