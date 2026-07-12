# Handoff: Confessional Christianity — Catechizing Your Child

## Overview
"Confessional Christianity" is a web app that helps a parent catechize a child — walk them through a historic catechism (starting with the Westminster Shorter Catechism), question by question, with the underlying scripture and a prayer tying it together. The app also hosts a reference library of confessions/catechisms and reflection essays, which is the site's primary organic (SEO/search) entry point. Full product rationale, scope, and rules are in `PRD.dc.html` — read it first; this README summarizes the parts relevant to implementation and maps PRD sections to the mockup screens.

## About the Design Files
The files in this bundle (`mockups.dc.html`, `PRD.dc.html`) are **design references built in HTML/CSS**, not production code to copy directly. `mockups.dc.html` is an exploration canvas: it contains multiple **turns** of iteration on the same screens, stacked in reverse-chronological order (newest turn at the top), each screen a static 390×844px mobile-frame mockup with inline styles. The task is to **recreate these designs in the target codebase's existing environment** (React Native, native iOS/Android, or whatever web stack the app already uses) using its established component patterns, navigation, and state management — not to embed this HTML.

**Turn 7, the entry funnel.** The PRD and turns 1–6 describe the app largely from a signed-in state. Turn 7 (screens `7a`–`7e`) rebuilds the *first-run* funnel — landing → first question → save prompt → signed-in home — optimized for time-to-value: a new visitor reaches a real catechism question with its Scripture before any signup wall, and an account is only requested once they act on saving progress. Turn 7 also renames **"program" to "catechism"** throughout its screens (the thing being personalized is the catechism itself — Westminster Shorter, Heidelberg, a kids' catechism — not an abstract "plan"/"program"). This is a terminology and IA change that should be treated as superseding the PRD's "program" language and routes wherever the two conflict — flag this to product/content rather than silently reconciling it.

**Latest addition — turn 8, the aha screen deepened.** Screen `7c` — the single most important screen in the app — is superseded by `8a`. It keeps 7c's core promise (question + Scripture + save + next, no wall) but goes further: every clause of the catechism answer gets its own inline citation marker, and tapping a clause swaps in that clause's specific proof text (see Interactions below) instead of bundling every verse into one block. Two new entry points sit between the Scripture and the existing Save/Next bar — **`8b`, "Pray About This"** (a short prayer written directly off the question) and **`8c`, "Reflections"** (short essays scoped to that one question, not the catechism generally) — both one tap from the question and one tap back.

## Fidelity
**High-fidelity.** Colors, typography, spacing, and copy in the mockups are final/intended, not placeholder. Recreate pixel-close using the codebase's own component library where one exists; where none exists, these values are the source of truth.

## Which Screens Are Current (read this before building)
`mockups.dc.html` is an options/iteration log, not a clean spec — later turns supersede earlier ones. Build only the **current** screen for each concept:

| Concept | Current screen id(s) | Superseded / alternates (do not build) |
|---|---|---|
| **Signed-out landing (new visitor)** | **7a** *and* **7b** — two directions, both still live for a decision: 7a lets a visitor browse catechisms with zero input, 7b asks only the child's name + age up front (age <8 triggers an inline recommendation of the kids' catechism) and picks a sensible default catechism. Pick one, or A/B test — do not build both as permanent paths. | — (no prior turn addressed the signed-out state at all) |
| **First question / "aha" screen** | **8a** (supersedes 7c) — question, its Scripture cited per-clause, a quiet "Save progress" affordance, "Pray About This" and "Reflections" entry points, and "Next Question →" all on one screen, reachable with zero account. This is the single most important screen in the app; do not add a signup interstitial before it. | 7c |
| Prayer for the current question | **8b** — reached only from 8a's "Pray About This" row; one tap back to 8a. | — |
| Reflections on the current question | **8c** — reached only from 8a's "Reflections" row; one tap back to 8a. Scoped to the single question, not a general essay index (that's `1e`). | — |
| **Save / account-creation gate** | **7d** — reached only when the visitor deliberately taps "Save progress," never automatically. Must remain dismissable ("Not now, keep going") without losing the in-progress session. | — |
| Homepage child switcher (signed in) | **7e** (supersedes 6c — same circular avatar row and tap-to-switch pattern, but copy changed from "Programs"/"Plan" to "Catechisms"/child's catechism, and includes an "Explore Other Catechisms" row) | 6c, 1a, 3a, 5a/5a-2 (segmented pill), 6b/6b-open (large dropdown chooser) |
| Add a child (onboarding) | **5b** | — |
| Choose child to start a program | **5c** | — |
| Program landing page | **5d** | 2b |
| Program complete | **5e** | — |
| Session — new question | **4a** | — |
| Session — review | **4b** | — |
| Session — scripture & prayer | **4c** | — |
| Session — done | **4d** | 2c (old single-page session) |
| Programs index (`/programs`) | **2a** | — |
| Teaching notes / enrichment | **2d** | — |
| Program pacing/configuration | **2e** | — |
| Library entry + commentary | **1b** | — |
| Library entry, no commentary | **1c** | — |
| Search results | **1d** | — |
| Reflections index | **1e** | — |
| Library index | **1f** | — |
| Confession table of contents | **1g** | — |
| Memorization overview | **1h** | Note: PRD §5.6 folds standalone "memorization" into program tracking; §14 defers a dedicated drill screen. Treat 1h as a reference for the mastery-heart visual only, not a screen to build as-is — confirm with product whether a standalone `/memorization` page is in scope. |
| Series index | **1i** | — |
| Author page | **1j** | — |

Each screen's `id` attribute in `mockups.dc.html` matches the ids above — jump to `#5d` etc. in the file, or open it in a browser and click the in-page links (screens link to each other via `<a href="#id">`, roughly approximating the real app's navigation).

## Design Tokens

**Colors**
- Background (page): `#e9e6dd` (canvas only, not app chrome)
- Background (app/card): `#faf9f6`
- Ink (primary text): `#211e19`
- Ink (secondary/meta text): `#5c574c`
- Ink (tertiary/labels): `#8a8378`
- Hairline borders: `#ddd8cd` / `#e2ddd0`
- Subtle fill (cards, active rows): `#f4f2ea`
- Muted border/dotted accents: `#c9c4b6`
- **Ochre accent** (`#ab7e2e`) — the app's one departure from monochrome, scoped strictly to progress bars and the "mastered" heart glyph state (PRD §5.6). Do not extend it elsewhere without checking PRD §16 open questions.
- Child-avatar colors (screen 6c, arbitrary per child, rotate through a small set): `#8a6a4f`, `#5c7a6e`, `#6d6a8c`

**Typography**
- Display/label font: **Cinzel** (weights 400/500/600/700), tracked uppercase for nav, labels, headings, buttons — letter-spacing ~0.08–0.14em depending on size.
- Body/reading font: **Marcellus** (roman + italic), used for prose, descriptions, and quoted material. Reading column max-width 44rem (~680px) per PRD §6.
- Load both from Google Fonts (see `<helmet>` in `mockups.dc.html` for exact `@import`/`<link>` URLs).
- Body copy: ~1.125rem (18px), line-height 1.8, color `#211e19`.
- Small-caps tracked labels: minimum 10–11px, generous letter-spacing (never smaller — PRD §11 accessibility rule).

**Layout**
- Mockups are drawn at a 390×844 mobile frame (iPhone-sized viewport) with a 14px card radius and soft shadow (`0 16px 44px rgba(33,30,25,0.12)`); status bar row is decorative chrome only, not part of the design.
- Session screens (4a–4d) are fixed-height (844px) single-screen steps — no scrolling within a step, per PRD §5.2.
- Reading/article pages: 44rem max-width column, 44px mobile gutters, blockquote = 2px solid black left border + italic + trailing tracked-caps scripture citation.

**Progress / mastery indicator (PRD §5.6)**
Single heart glyph, three states, used identically in session, program TOC, and any overview: outline = not started, muted fill = in rotation/reviewing, filled ochre (`#ab7e2e`) = mastered. Always paired with a descriptive `aria-label` (e.g. "Mark Q. 7 recited without help") — never a bare icon.

## Interactions & Behavior
- **Signed-out entry (7a/7b → 7c):** no auth check gates the first question. If 7b's age field is under 8, surface the kids'-catechism recommendation inline (not as a separate step) and let the visitor override it before continuing.
- **Per-clause Scripture (8a):** the answer text is broken into clauses (e.g. "glorify God" / "enjoy him forever"), each with its own small numbered marker. Exactly one clause's proof text is shown at a time in a fixed-height panel below the answer — the first clause's is shown by default; tapping any other clause swaps the panel to that clause's verse (own state, not navigation — no page change, no scroll jump). This is a deliberate negative-space choice: showing all citations open at once was tried and rejected as too dense for the app's single most important screen.
- **Pray / Reflections entry points (8a → 8b/8c):** both are lightweight, one-tap-in/one-tap-back detours from the question — never a forced step, never blocking "Next Question." They should feel like optional depth, not required reading.
- **Save gate (8a → 7d):** now hangs off `8a` (7c's successor) rather than 7c itself. Triggered only by explicit intent (tapping "Save progress"), never by a timer, page count, or on attempting "Next Question." "Not now, keep going" must return to the session with state intact (local/session storage until an account exists) — never lose the child's place because they declined to sign in.
- **Child switching (7e, ex-6c):** tapping any avatar other than the active one navigates straight into that child's session — no intermediate confirm step. The "continue" card below has no button of its own; the entire card is the tap target into today's session.
- **Starting a program (5c):** choosing a child is mandatory and inline — either pick an existing child or "+ Add a Child" (→ 5b) before the program starts.
- **Session flow (4a→4b→4c→4d):** linear, one concept per screen, quiet dot/arrow progression (new material → review → scripture & prayer → done). No back-tracking UI shown in mockups; confirm with product whether back navigation is needed.
- **Program completion (5e):** two forward actions only — restart the same program, or start a different available program for the same child. Completion never deletes history (PRD §5.7).
- **Search vs. canonical pages (PRD §7):** `/search` is the only place that shows match counts or the literal query; every other page (library entry, essay, teaching notes) must never reference "matches" or a query string, even when arrived at from search.
- **Discoverability marker (PRD §10):** a small dagger (†) glyph, plus the label "COMMENTARY" where there's room, marks any library entry that has an essay — no color, no badge shape.

## State Management (high-level, see PRD §5 for full detail)
- **Guest/pre-account state (turn 7):** a signed-out visitor's child name, age, chosen catechism, and current question index must persist locally (e.g. local storage / device storage) across the landing → question → next-question loop, so declining the save prompt never resets progress. On account creation, that local state is claimed/migrated into the real per-child record rather than starting over.
- A **catechism** (formerly "program") belongs to exactly one child; a household may run multiple programs across multiple children concurrently.
- Program state per child: current question index, per-question mastery state (not-started / reviewing / mastered), which questions have authored prayers (first program's content is populated progressively, not all 107 at once).
- Pacing/configuration (PRD §5.4) is per-program, per-household: new questions per session, review depth (recent window / full rotation / weak-only), mastery definition (unprompted recitation streak / manual parent judgment / fixed exposure count), sessions per week, whether scripture shows every time or only on introduction.
- Child records: name + age only (age drives pacing defaults, not birthdate — PRD §12). No standalone "manage children" screen; children are added inline from onboarding or from `/programs`.

## Assets
No photography, icons are hand-drawn inline SVG (magnifying glass, hamburger menu — see `mockups.dc.html` for exact markup) or Unicode glyphs (†, ♡, chevrons). No external image assets to source.

## Information Architecture (PRD §4 — copy verbatim, this is the full route map)
```
/                                     homepage
/programs                            browse all programs
/programs/[slug]                     program landing
/programs/[slug]/session             today's session
/programs/[slug]/[entry]/notes       teaching notes (deferred beyond first program, §5.3)
/programs/[slug]/pacing              pacing/configuration controls
/reflections                         essay index
/reflections/[slug]                  single essay
/authors/[slug]                      author page
/library                             index of all confessions/catechisms
/library/[confession]                document table of contents
/library/[confession]/[entry]        one canonical entry
/search                              full search
```

## Files in This Bundle
- `PRD.dc.html` — full product requirements document (open in a browser; this is the authoritative spec for scope, rules, and rationale).
- `mockups.dc.html` — all mobile mockup screens across 7 turns of iteration (open in a browser; use browser find/anchor-jump on screen ids like `5d`, `4a`, `7c`).
- `doc-page.js`, `support.js` — runtime helpers the above two files depend on to render; not part of the target app, no need to port them.

## Open Questions (carried from PRD §16 — resolve before/while building)
- Final product name ("Confessional Christianity" vs. a renamed, more catechizing-forward brand).
- Auth/account model (email+password vs. magic link vs. social login).
- Whether non-catechesis programs (Bible-in-a-year, topical devotionals) get the same eventual "teaching notes" depth.
- Whether the ochre "mastered" accent should extend beyond program tracking (current recommendation: no).
- Donation routing mechanism/partner for the "100% to missionary church planters" promise (§13) — this is a legal/accounting prerequisite, not a copy detail.
