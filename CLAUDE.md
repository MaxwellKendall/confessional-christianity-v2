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
- `scripts/`: Algolia indexing, prayers authoring, `ios/sync-content.mjs` (copies `content/` into the app bundle).
- `ios/App/`: the app. `project.yml` is the XcodeGen spec (the `.xcodeproj` is generated; don't hand-edit it). `Sources/`, `Widget/` (Home Screen widget, App Group `group.com.confessionalchristianity.app`).
- `ios/DomainKit/`: SwiftPM package with the app's pure logic and bundled content; its tests run on the host Mac.
  `QuoteCard/` is the share-image renderer (TKL-842), with its own copy of the fonts in `QuoteCardFonts/`. Its snapshot
  fixtures are in `Tests/DomainKitTests/Fixtures/QuoteCard/`: re-record `native/` with `QUOTE_CARD_RECORD=1 swift test`
  after an intended visual change; regenerate `prototype/` (the approved TKL-840 design via headless Chrome) with
  `ios/DomainKit/scripts/quote-card-prototype/render.sh`. Lord's Day feed cards share as square PNGs through it
  (TKL-1060, `LordsDayFeedCard.quoteCardContent`/`sharePNG`); their snapshots are in `Fixtures/QuoteCard/lordsDay/`.
- `ios/AppStoreScreenshots/`, `ios/design-assets/`: listing art.
- `infra/`: AWS CDK (TypeScript) for accounts, the Cognito pools (see "Accounts" below and `infra/README.md`).
  `ios/App/Resources/amplify_outputs.{dev,prod}.json` are its generated, committed client configs.

## Setup
- Node 22, `npm ci`.
- Each worktree needs the gitignored `.env.local`: copy it from the main checkout (`cp ../confessional-christianity-v2/.env.local .`). Names are in `.env.example`; never print values.
- Xcode 27, XcodeGen at `/opt/homebrew/bin/xcodegen`. Bundle id `com.confessionalchristianity.app`, team `7GZKY29XJH`, automatic signing. iOS 17.0 target, Swift 6.
- Simulator: **"CC iPhone 17 Pro"** (its own, so runs don't fight barbrabell's shared "iPhone 17 Pro").
- Screenshots without taps (DEBUG launch args, `xcrun simctl launch <dev> com.confessionalchristianity.app -Key value`; the simulator
  runs headless, so there is no window to click): `-VerseReaderFixture verse|long|citations|notes|end|loading|error` (plus
  `-ReaderSettingsSheet YES`, `-ReaderConfessionsSheet YES`, `-ReaderConfessionsClause YES`, TKL-972),
  `-ReaderChapterReference Rom.8.28`, `-ProofTextSession catechizing-shorter-catechism:32[:Rom.8.30]` (session at Q. 32, optionally
  with the proof-text reader pushed) plus `-ProofTextReaderCard verse|notes|end`, `-LordsDayLandingFixture week|sunday|drafting|review|none|first|offline|error|keptPlusEmpty` (the Lord's Day landing page in that state from an in-memory store, TKL-1063; `keptPlusEmpty` computes its state from a kept sermon plus an empty pending review, with the "nothing to keep" panel that opens it, TKL-1103; `-LordsDayStackPage N` sets the stack's top page, default 4; `-LordsDayStackSermon N` starts the stack swiped sideways to sermon N, TKL-1096; `-LordsDayReelAt 0:4` opens the reel at sermon 0, page 4; `-LordsDayReelBubble YES` shows the scrub bubble), `-LordsDayReviewFixture filling|complete|smyrna|empty` (reviewing drafted cards, TKL-863; `empty` drafts 0 cards and shows Discard these notes, TKL-1103: sample drafts replayed into a throwaway
  folder; `filling` stays mid-fill; `smyrna` drafts the Revelation 2:8-11 note into an empty note, so its title, preacher and passage come from the drafted `sermon` event, TKL-1061) plus `-LordsDayReviewCard p0-1|drafting` (open at that card), `-LordsDayReviewOpenDetails title|preacher|passage|church|date` (the sermon details sheet open with that field focused, or its calendar shown for `date`, TKL-1085), `-LordsDayReviewApplyDetails "Title|Preacher|Passage|Church"` (saves those details once drafting is done, to show the header after Done), `-LordsDayReviewEditCard p0-0`, `-LordsDayReviewRedrafting p0-0`, `-LordsDayBatchFixture picker|cap|groups|queue|review|date|keep` (batch import, TKL-1108: `picker` shows the intro, `cap` shows 30 selected pages, `queue` shows the review pager, `date` opens Edit details on Date; seven sample pages read into three sermons on the grouping screen; `review` opens the sermon whose date was guessed; `keep` writes to the app's store, keeps all three and shows the app, so with `-StartTab lordsDay -OpenJournal YES` it is the journal with three imported Sundays), `-LordsDayCaptureFixture camera|strip|type|details`
  (the notes camera with a sample page), `-LibraryEntry westminster-confession-of-faith:WCoF-2-1` (one library entry page), `-StartTab today|catechism|lordsDay` (open on that tab), `-OpenJournal YES` (with `-StartTab lordsDay`, pushes the sermon journal, TKL-944) plus `-JournalFixture empty|1|50|500` (that many synthetic Lord's Days instead of the store), `-JournalLens time|scripture`, `-JournalQuery <words>`, `-JournalYear 2025`, `-JournalMonth 3`, `-JournalBook Rom`, `-JournalChapter 8`, `-JournalZoom years|months|sundays`, `-JournalOpenSermon first`, `-JournalOpenReel first|<n>` (the reel at that hit's sermon, as its Read button does, TKL-1085); the app logs `year grid ready: N Lord's Days in M ms` (category `journal`), `-OpenSheet settings|addChild` (open that sheet on Today) plus `-AddChildName <name>` (Add a child pre-filled, as if Add was tapped: a seeded name shows the duplicate error), `-SeedChildren "Samuel:9,Thomas:4"`
  (those children at those questions, only when there are none yet: a fresh install is the empty state), `-SeedSermonWeek YES` (the sample sermon
  week, `SampleSermonWeek`, saved to the app's store, only when it has no notes; the old week feed and `-LordsDayFeedFixture` were retired in TKL-1085: Today then shows the week's sermon stack at the card the Lord's Day tab
  was last on, not a card per weekday, TKL-941; Today's Settings and Add a child pairs: `-SeedChildren "Samuel:9,Thomas:4" -OpenSheet settings|addChild`
  against `render.sh settings-full-<theme>` / `addchild-full-<theme>`), `-EsvOffline YES` (reader,
  verse cards and the cards generator act offline), `-LordsDayCardsEndpoint <url>` (DEBUG-only override for `LiveCardsGenerator`, e.g. a local dev server; Release always hits the hosted endpoint), and
  `-SkipNotificationOffer YES` (always pass it: an unanswered notification prompt survives reinstalls until the simulator reboots),
  `-OpenReminders YES` (with `-OpenSheet settings`, opens Reminders), `-FireReminder weekday|saturday|resurfaced|catechism`
  (makes two sample sermon weeks in an in-memory store and routes the planner's notification payload through the app),
  `-OpenSignIn YES` (with `-OpenSheet settings`, opens the sign-in sheet on top), `-OpenSignOutConfirm YES` (with `-OpenSheet settings`, opens the sign-out confirmation sheet), `-SettingsAutoSignOut YES` (confirms sign-out and clears local synced data once restored), `-GuestMergeFixture full|loading|error` (the "Keep what's on this phone in your account" merge screen, TKL-1070), `-GuestMergeAutoConfirm YES` (auto-confirms the guest merge screen on first sign-in),
  and for signing in without taps (TKL-928, dev pool only): `-SignInEmail otp-test@cc-dev-mail.barbrabell.com -SignInAutoSend YES -SignInCodeFile /tmp/code.txt`
  sends the code through the sheet, then types and submits each new code written to that host file (2 s later, for a screenshot);
  fill the file from `infra/scripts/inbox-code.sh`.
  The app follows the system light/dark setting (there is no launch arg): `xcrun simctl ui <dev> appearance light|dark`.
- Design: colours, type, shapes and shared components are Chapel, in `ios/App/Sources/DesignSystem.swift`; no hex in screens.
  Pair a screen with the approved home and navigation prototype (TKL-885):
  `ios/scripts/prototype-shots/render.sh today-full-dark out.png [simulator.png]` (states are listed in the script).

## Test (from the repo root)
| Suite | Command | Runtime |
|---|---|---|
| web unit | `npm test` (vitest, 392 tests, incl. `scripts/**/*.test.mjs`; 60 s timeouts for the loaded build Mac) | ~1 s |
| web build | `npm run build` (needs `.env.local`; ESLint enforced) | ~15 s |
| DomainKit | `cd ios/DomainKit && swift test` (443 tests: 325 Swift Testing + 118 XCTest) | ~15 s |
| iOS build | `cd ios/App && xcodegen generate && xcodebuild -scheme ConfessionalChristianity -destination 'platform=iOS Simulator,name=CC iPhone 17 Pro' -derivedDataPath ../../build/dd build` | 15+ min cold (AWS SDK), ~1 min warm |
| infra | `cd infra && npm ci && npm test` (vitest CDK assertions, 20 tests) | ~6 s |
| iOS UI (loop events) | `cd ios/App && xcodegen generate && xcodebuild test -scheme ConfessionalChristianity -destination 'platform=iOS Simulator,name=CC iPhone 17 Pro' -derivedDataPath ../../build/dd -only-testing:ConfessionalChristianityUITests` (not a Verify check; sends real events) | ~3 min |

### Lord's Day loop analytics (TKL-947)
Three events go to PostHog (`https://us.i.posthog.com`, the project whose capture key is `NEXT_PUBLIC_POSTHOG_KEY` on the
old `confessional-christianity-node` Vercel project; the v2 project's copies are empty): `lords_day_sermon_kept`
(`card_count`), `lords_day_day_opened` (once per local day), `lords_day_card_shared` (`kind`). DomainKit's
`LoopAnalytics.captureRequest` is the only place a body is built; `LoopAnalyticsTests` asserts each body byte for byte.
The key (write-only, public by design) is `POSTHOG_KEY` in `ios/App/project.yml`. Every event has `env` = `debug` or
`release`; filter `properties.env = 'release'` for real use. The app logs each send's status (category `analytics`):
`xcrun simctl spawn "CC iPhone 17 Pro" log show --last 10m --predicate 'category == "analytics"'`. PostHog's capture
endpoint answers 200 even to an unknown key; `POST /flags/?v=2` with the key returns 401 when the key is wrong.
Changing what is sent means updating `PrivacyInfo.xcprivacy`, `/privacy` and the App Store privacy answers together
(`test/loopAnalyticsDisclosure.test.ts` checks the first two).

### Lord's Day cards eval (paid, never in `npm test`)
`POST /api/lords-day/cards` (src/lib/lordsDay/handler.ts has the contract) drafts cards from sermon-note photos with
Gemini. The same call also returns `sermon` (title, preacher, passage, church, serviceDate; each null unless the notes say it,
TKL-1061): a `sermon` stream event per page that names something, merged on `done`; the app fills only the note's empty fields. Server env: `GEMINI_API_KEY`, optional `GEMINI_CARDS_MODEL` (default `gemini-3.8-flash`), `COGNITO_USER_POOL_ID`,
`COGNITO_CLIENT_ID`. Golden set: `evals/lords-day-cards/` (12 real note photos, `truth.json`). Run from the repo root:
`set -a; source ~/dev/.secrets.env; set +a; npm run eval:cards` (prefix `GEMINI_CARDS_MODEL=<model>` to compare models,
`EVAL_CASES=sermon-02` for one case); ~1-2 cents per case (12 photos + 3 typed-note cases). Prints per-case PASS/FAIL, the `sermon` score for cases with `sermon` truth (the run fails if any field is made up) and a total, and writes
`evals/lords-day-cards/results/<model>.json`. A 402 from Gemini means the key's prepaid credits are spent (Maxwell tops up).

## Verify checks
A change lands only with these green: `npm test`, `npm run build`, `swift test` in `ios/DomainKit`, and the iOS build.
A change under `infra/` also needs `cd infra && npm test`.
A UI change also gets a simulator screenshot (iOS) or a browser screenshot (web).

## Land
Fast-forward to `origin/main` (no PRs): branch a worktree from `origin/main`, commit, `git push origin HEAD:main`.
Never commit in the main checkout: it often holds Maxwell's uncommitted work on another branch.

## Deploy
- **Web:** Vercel serves https://confessionalchristianity.com (`server: Vercel`). Whether a push to `main` deploys by itself is unverified; check the Vercel project before relying on it. Post-deploy: `/`, `/library`, `/search` return 200.
- **Maxwell's iPhone 17 Pro:** install **only when he asks** (never after every landing; routine builds reach him on TestFlight), and only with `npm run device-install -- --device 00008150-001035213A44C01C`.
  Run it from a clean checkout of landed code. It builds Release and records each successful install in the
  shared git directory. Add `--dry-run` to print the plan without building or installing.
- **iOS:** `npm run ios:release` (`scripts/ios/release.mjs`, TKL-814) from a worktree of `origin/main`. It reads every build
  ever uploaded from App Store Connect, sets `CURRENT_PROJECT_VERSION` in `ios/App/project.yml` to one above the highest (local
  or uploaded), runs `xcodegen generate`, `xcodebuild archive`, `-exportArchive -allowProvisioningUpdates` to a local `.ipa`,
  `xcrun altool --validate-app`, then `xcrun altool --upload-app`, then polls App Store Connect until the build is `VALID` (up to
  45 min) and prints `RESULT build=N marketing=M signing=S uploaded=yes state=VALID`. Add `--marketing-version 1.2` for a new App
  Store version. `--dry-run` does everything up to and including `altool --validate-app` (a real check against Apple with the
  key) but never uploads or changes a file (~8 min). Logs: `build/release/{archive,export-key,export,validate,upload}.log`.
  It never submits for review or releases. After a real run, commit and push the bumped `project.yml` and regenerated
  `project.pbxproj` (if anything fails before the upload it restores them; after an upload attempt it keeps the bump).
  **Authentication:** the App Store Connect API key (`ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_PATH` in `~/dev/.secrets.env`, same
  team as barbrabell; never printed) authenticates every call to Apple: reading builds, validate, upload and polling.
  **Signing (TKL-880):** the export tries the API key first (`signing=asc-key`). Today Apple refuses it ("not given access to
  cloud-managed distribution certificates") and there is no local `Apple Distribution` identity, so the script falls back to
  cloud signing through the Xcode account signed in on this Mac (`signing=xcode-account`). That fallback is the one remaining
  dependency on the account; it goes away once the key is allowed cloud-managed distribution certificates or this Mac holds an
  `Apple Distribution` identity, with no code change. Versions stay on manual release.
- **iOS build numbers so far** (App Store Connect, checked 2026-11-20): builds **1** and **2** were version `0.1.0` (Aug 2026, expired);
  build **3** is version `1.1` (uploaded 2026-11-20). The `0.1.0` train is closed (a `0.1.0` build was approved), so uploads need a
  `MARKETING_VERSION` above it. The App Store *version record* is `1.0` READY_FOR_SALE and points at build 2, so don't infer the next
  build number from the store version. Next build number is one above the highest ever uploaded, expired or not; query
  `/v1/builds?filter[app]=6797692942` (app id) rather than the builds list on the app, which hides expired builds.
- Internal TestFlight group: **"updates"** (`isInternalGroup: true`, `hasAccessToAllBuilds: true`, so new builds reach it once processed). A tester stays `NOT_INVITED` and gets no email while no build is valid; once one is, send the invite with `POST /v1/betaTesterInvitations`.
- Content changes (`content/`) reach the app only through `npm run ios:sync-content` and a new build (TKL-683 would decouple that).

## Accounts (`infra/`)
Cognito user pools, sign-in by a code emailed to the person (`USER_AUTH` + `EMAIL_OTP`; codes are 8 digits, sign-up
codes 6). No passwords: the `NoPassword` trigger scrambles any password on confirmation and before each sign-in,
so clients must send `PREFERRED_CHALLENGE=EMAIL_OTP`; after a pool change run `AWS_PROFILE=aicoach-dev
infra/scripts/password-probe.sh` (dev, prints `PASS`). CDK app in `infra/`, account `397614038040`, profile `aicoach-dev`, us-east-1. Four stacks:
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
- Prod: runs on the studio pool `Studio-prod` (`us-east-1_80qmmpRpD`, `confessional` client `138ua04t4vtitttt5uaq72iji2`, managed in `~/dev/studio-platform`, TKL-1039/TKL-1040/TKL-1041). Sends as `Confessional Christianity <no-reply@confessionalchristianity.com>` through the existing verified SES identity from `ConfessionalChristianityMail-prod` (DNS on Vercel). Regenerate `ios/App/Resources/amplify_outputs.prod.json` via `AWS_PROFILE=aicoach-dev npm run outputs prod` in `infra/` (combines `StudioIdentity-prod` auth with `ConfessionalChristianity-prod`'s `AccountSyncUrl`, TKL-1071).
- **Website (`/account`, TKL-1043):** signs in against the same studio `confessional` client (prod: pool `us-east-1_80qmmpRpD`, client `138ua04t4vtitttt5uaq72iji2`; studio dev: pool `us-east-1_7As1IQnUY`, client `7j0hcan1l99f805snqr73eci21`) via a small zero-dependency Cognito JSON-RPC fetch client (`src/lib/account/`). Public env vars: `NEXT_PUBLIC_COGNITO_USER_POOL_ID` and `NEXT_PUBLIC_COGNITO_CLIENT_ID` (unset → "Accounts are coming soon."). Server-side token verification (`/api/lords-day/cards`, `/api/account/me`) uses `@studio/auth` (`packages/studio-auth/`, vendored from `studio-platform/packages/auth`), reading `STUDIO_USER_POOL_ID` / `STUDIO_CLIENT_ID` with fallback to `COGNITO_USER_POOL_ID` / `COGNITO_CLIENT_ID`.
- Account sync uses DynamoDB behind Cognito-authorized AppSync (TKL-891, TKL-1071), authorizing tokens from the studio pool's `confessional` client (dev also keeps `ConfessionalChristianity-dev` as an extra authorizer until TKL-965). Account deletion invokes `ConfessionalChristianity-sync-delete-{stage}` from `StudioIdentity-{stage}`'s `DeleteAccount` Lambda (`infra/SYNC.md`).
- **The app (TKL-928, TKL-1041):** amplify-swift `exactVersion: 2.62.0` (Amplify + AWSCognitoAuthPlugin); `AuthService` signs up first
  (passwordless, 6-digit code, then auto sign-in) and falls back to sign-in (8-digit `EMAIL_OTP` code) on `usernameExists`,
  because the pool hides unknown users from sign-in but not from sign-up. Debug bundles `amplify_outputs.dev.json` (`ConfessionalChristianity-dev`, until TKL-965), Release
  `amplify_outputs.prod.json` (`Studio-prod`); without a valid file the app is a guest, Settings has no Account section, and `device-install` refuses. A cold iOS
  build compiles the AWS SDK and takes well over 10 minutes.

## Gotchas
- The cut prayer list's people table must not come back (TKL-869): `npm run check:removed-refs` (`scripts/checks/removed-refs.mjs`,
  also run by `npm test`) lists every tracked reference to it except the allowed files (the check itself, plus the old migration pair
  and removal test, gone since TKL-904) and exits 1 if there is one. Use it instead of a bare `rg -i` for the table name.
- The Algolia Admin key is for `scripts/` only; the browser gets the search-only key.
