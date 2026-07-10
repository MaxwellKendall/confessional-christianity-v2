# Domain Model & ID Conventions

This is the single most important thing to understand before working on search,
routing, or the reading pages. The type declarations live in
[types/domain.d.ts](../types/domain.d.ts); this file explains the conventions
those types encode and — critically — the several different "names" the same
document goes by.

## The core structure: `contentById`

Every confession, catechism, and set of theses is flattened into one map of
`id -> `[`ConfessionEntry`](../types/domain.d.ts). A representative entry:

```json
{
  "id": "WCoF-1",
  "parent": "WCoF",
  "title": "Chapter 1: Of the Holy Scripture",
  "isParent": true,
  "number": 1
}
```

- `isParent: true` marks a **structural** node (a chapter, or a Heidelberg
  "LORD's Day"). `isParent: false` marks a **leaf** node with actual confession
  `text` (and often `verses`, its proof-text citations).
- The tree is implicit: there is no `children` array. A node's children are
  every entry whose `parent` equals its `id`. A top-level entry's `parent` is
  the bare **document id** (no dash), e.g. `WCoF`.

Two copies of this map exist for historical reasons:
- built at runtime by [lib/confessionContent.js](../lib/confessionContent.js)
  (used by the reading pages), and
- prebuilt as [dataMapping/content-by-id.json](../dataMapping/content-by-id.json)
  (used by the search-result components).
Both derive from the same `normalized-data/**` source.

## The id grammar

Ids are dash-delimited paths under a document id:

- `WCoF-1` — Westminster Confession, chapter 1 (a parent)
- `WCoF-1-2` — chapter 1, article 2 (a leaf)
- `WSC-1` — Westminster Shorter Catechism, question 1 (catechisms are flat: no
  article level)
- `HC-1-12` — Heidelberg, LORD's Day 1, Q&A 12
- `CoD-1-articles-3` — Canons of Dort, head 1, article 3
- `CoD-1-rejections-2` — Canons of Dort, head 1, rejection 2 (Dort is the one
  document with a named article/rejection split)

Helpers for working with ids live in [helpers/index.js](../helpers/index.js):
`getDocumentId`, `isDocumentId`, `compareEntryIds` (document-order sort),
`entryIdToPathSegments` (id → URL path), `sliceConfessionId`.

## The document-alias problem (read this)

**The same document is referred to by several different identifiers, and much
of the code in `helpers/` and `dataMapping/` exists to translate between them.**
This is the primary source of accidental complexity in the codebase. The four
vocabularies, using the Westminster Confession as the running example:

1. **Canonical content-id prefix** — how it appears as the prefix inside
   `contentById` ids: `WCoF`. Others: `CoD`, `TBCoF`, `TAoR`, `ML9t`, `CfYC`.
   These are the ids in `slugByDocumentId` and the *values* of
   `parentIdByAbbreviation`.
2. **Concise / Algolia doc id** — the abbreviation used in the search UI and
   Algolia records: `WCF`. Produced by `getConciseDocId` (drops "of"/"the", so
   `WCoF` → `WCF`).
3. **URL slug** — the human-readable route segment:
   `westminster-confession-of-faith`. Lives in `slugByDocumentId` and
   `confessionPathByName`.
4. **Facet / search aliases** — the many spellings a *user* might type, matched
   by the regexes in `helpers/index.js` and mapped by `confessionCitationByIndex`
   (e.g. `WCF`, `WCOF`, `WCoF` all resolve to the same document; `CD`/`COD`,
   `39A`/`TAR`, `95T`/`ML9T`, etc.).

The translation surface, all in [dataMapping/index.js](../dataMapping/index.js)
and [helpers/index.js](../helpers/index.js):

- `confessionCitationByIndex` — alias → `[displayName, ...facetLevelLabels]`
- `parentIdByAbbreviation` — concise/alias id → canonical content-id prefix
- `slugByDocumentId` — canonical prefix → URL slug
- `facetNamesByCanonicalDocId` — doc id → the names of its facet levels
- `getConciseDocId` / `getCanonicalDocId` — string → concise / canonical id
- `getConfessionalAbbreviationId` (in [scripts/helpers](../scripts/helpers/index.js))
  — display title → first-letter abbreviation

> If you only remember one thing: **"the id" is ambiguous.** When reading a
> function, first work out *which* vocabulary its input and output are in.

## Facet parsing: `parseFacets`

`parseFacets(searchString)` (in [helpers/index.js](../helpers/index.js)) turns a
user's query into Algolia [`facetFilters`](https://www.algolia.com/doc/api-reference/api-parameters/facetFilters/).
The return type is [`FacetFilters`](../types/domain.d.ts) — an array where:

- a **bare string** (`"id:WCoF-1-2"`) is an **AND** term, and
- a **nested array** of strings is an **OR** between those filters.

So `parseFacets('westminster standards')` returns a single nested array (match
WSC *or* WLC *or* WCF), whereas `parseFacets('WCF.1.2')` returns
`['id:WCoF-1-2']`. This "2d array is OR" rule is Algolia's, and it is the
contract the search page depends on. It is covered by data-driven cases in
[test/helpers.test.js](../test/helpers.test.js).

## Document metadata registry

[lib/catechisms.js](../lib/catechisms.js) is the single source of truth for
each document's *display* metadata (name, short name, item count, item label,
tradition, description). `CREEDAL_DOCUMENTS` holds all documents; `CATECHISMS`
(the children-tracking subset) is **derived** from it plus an age-range overlay,
so the two cannot drift. See [`CreedalDocument`](../types/domain.d.ts).

## Adding a new document (the checklist)

Because of the alias problem above, adding a document touches several places.
Keep them in agreement:

1. `normalized-data/**` — add the source JSON (`{ content: ConfessionEntry[] }`).
2. `dataMapping/index.js` — add to `confessionPathByName`, `slugByDocumentId`,
   `parentIdByAbbreviation`, `confessionCitationByIndex`,
   `facetNamesByCanonicalDocId`, and `DOCUMENTS_WITHOUT_ARTICLES` if applicable.
3. [lib/confessionContent.js](../lib/confessionContent.js) — add the static
   import + `confessionDataByName` entry.
4. `helpers/index.js` — extend the facet regexes (`regexV2`, `documentFacetRegex`,
   etc.) with the new aliases.
5. [lib/catechisms.js](../lib/catechisms.js) — add a `CREEDAL_DOCUMENTS` entry.
6. Regenerate `dataMapping/content-by-id.json` via
   [scripts/populate-content-by-id.js](../scripts/populate-content-by-id.js) and
   re-run the Algolia population scripts.

> The number of steps here is itself the argument for eventually deriving all of
> section-2's tables from one registry. That refactor is intentionally deferred;
> this checklist is the interim safety net.
