// The resource taxonomy (mockup 10a): five kinds, each with its own visual
// treatment and its own action. External kinds (song, podcast, book, essay)
// open on the platform that hosts them (↗); original writing is ours alone,
// so it opens in the app (›). Client-safe — the fs-backed loader lives in
// resources.ts.
export const RESOURCE_KINDS = ['song', 'podcast', 'book', 'essay', 'original'] as const;

export type ResourceKind = (typeof RESOURCE_KINDS)[number];

/** Filter-chip and row labels, in the 10a chip order. */
export const RESOURCE_KIND_LABELS: Record<ResourceKind, { chip: string; row: string }> = {
  song: { chip: 'Songs', row: 'Song' },
  podcast: { chip: 'Podcasts', row: 'Podcast Episode' },
  book: { chip: 'Books', row: 'Book' },
  essay: { chip: 'Essays', row: 'Essay' },
  original: { chip: 'Original', row: 'Original' },
};

export const isResourceKind = (value: unknown): value is ResourceKind => (
  typeof value === 'string' && (RESOURCE_KINDS as readonly string[]).includes(value)
);
