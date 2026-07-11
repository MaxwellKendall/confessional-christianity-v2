# Confessional Christianity v2

A [Next.js 16](https://nextjs.org/) (App Router, React 19, TypeScript strict,
Tailwind 4) app for catechizing a child — a paced, scripture-rooted walk
through a historic catechism — with the confessions and catechisms of
historic Protestantism to read and search.

This is the greenfield rewrite of
[confessional-christianity-node](../confessional-christianity-node): the data
layer, indexing pipeline, and Supabase project were **ported**, the UI was
**rebuilt** against the design handoff. Production target:
<https://www.confessionalchristianity.com>.

## The three surfaces

1. **Programs** (the product, PRD §5) — a program belongs to one child; a
   session walks new questions, review, and scripture & prayer.
   Entry points: [src/app/page.tsx](src/app/page.tsx) (child switcher),
   [src/app/programs/](src/app/programs/), pure domain logic in
   [src/lib/programs.ts](src/lib/programs.ts).

2. **Library & Reflections** (the front door, SEO-critical) — fully static
   RSC pages for every document, entry, and essay, plus a canonical
   `/scripture/[osis]` page for every proof-text reference showing the ESV
   passage and each confession clause that cites it.
   Entry points: [src/app/library/](src/app/library/),
   [src/app/reflections/](src/app/reflections/),
   [src/app/scripture/](src/app/scripture/), loaders in
   [src/lib/library.ts](src/lib/library.ts) /
   [src/lib/reflections.ts](src/lib/reflections.ts) /
   [src/lib/scripture.ts](src/lib/scripture.ts).

3. **Search** — the existing Algolia indices (`aggregate` + `citations`)
   queried through the ported `parseFacets` grammar.
   Entry points: [src/app/search/](src/app/search/),
   [src/lib/algolia.ts](src/lib/algolia.ts).

## Data pipeline (ported from v1, unchanged)

- `normalized-data/**/*.json` — source of truth for confession text
- `dataMapping/content-by-id.json` — prebuilt id → entry map (server-only;
  never import from a client component)
- `scripts/` — Algolia indexing + data prep (standalone, uses the non-public
  Admin key)
- `content/commentary/<entryId>.md` — reflection essays (frontmatter: title,
  subtitle, author, date, optional slug/series/part)
- `content/programs/<slug>/prayers.json` — authored session prayers, written
  progressively
- `supabase/migrations/` — the single source of truth for the account schema
  (same live Supabase project as v1). **The programs migration
  (`20260710000000_programs_domain.sql`) must be applied before program
  features work.**

## URL continuity

`next.config.ts` 301s every v1 reading route (`/[confession]`,
`/[confession]/[...entry]`, `/study`) to its v2 home. The `[...entry]`
catch-all collapsed to a single dash-joined `[entry]` segment
(`/westminster-confession-of-faith/1/2` → `/library/.../1-2`).

## Development

```bash
npm install
npm run dev        # dev server on http://localhost:3000
npm test           # vitest (51 tests pinning the ported data layer + programs domain)
npm run build      # production build (ESLint enforced)
```

### Environment variables

See [.env.example](.env.example). The Algolia key split is intentional:
search-only key in the browser, Admin key confined to `scripts/`; the ESV key
is server-only (used by `/api/esv`).

## Further reading

- [docs/DOMAIN.md](docs/DOMAIN.md) — the id grammar and document-alias
  vocabularies (start here before touching search or routing)
- The migration plan that produced this repo lives at
  `~/dev/claude-context/confessional-christianity-v2-migration-plan.html`
