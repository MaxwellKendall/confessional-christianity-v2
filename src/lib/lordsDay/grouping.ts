import type { SermonDetails } from './cards';

// Batch import (TKL-1107): which pages of a many-sermon batch make one sermon.
// The app's rule is DomainKit's `SermonGrouping.propose`
// (ios/DomainKit/Sources/DomainKit/LordsDayBatchImport.swift); this port exists so
// the eval can score grouping from the cards call's `sermon` events, offline in
// `npm test` (evals/lords-day-cards/grouping.json) and live in `npm run eval:cards`.
// Both sides are tested against the same grouping.json cases.

export interface GroupingPage {
  /** ISO time the photo was taken (EXIF), or null when unknown. */
  takenAt: string | null;
  sermon: SermonDetails | null | undefined;
}

export const DEFAULT_GAP_HOURS = 6;

/** Lowercased letters and digits only, so "Benediction." and "benediction" match. */
const comparable = (value: string | null | undefined) => {
  const kept = (value ?? '').toLowerCase().replace(/[^\p{L}\p{N}]/gu, '');
  return kept || null;
};

const differs = (a: string | null, b: string | null) => a !== null && b !== null && a !== b;

/**
 * Groups of page indexes, in batch order. A page starts a new sermon when it names a title,
 * passage or date different from the sermon so far, or was photographed more than `gapHours`
 * after the page before; otherwise (including a page that names nothing) it continues it.
 */
export const proposeGroups = (pages: GroupingPage[], gapHours = DEFAULT_GAP_HOURS): number[][] => {
  const groups: number[][] = [];
  let title: string | null = null;
  let passage: string | null = null;
  let date: string | null = null;
  pages.forEach((page, index) => {
    const pageTitle = comparable(page.sermon?.title);
    const pagePassage = comparable(page.sermon?.passage);
    const pageDate = page.sermon?.serviceDate?.trim() || null;
    const before = index > 0 ? pages[index - 1].takenAt : null;
    const gapped =
      before !== null && page.takenAt !== null && Math.abs(Date.parse(page.takenAt) - Date.parse(before)) > gapHours * 3600_000;
    if (groups.length === 0 || gapped || differs(pageTitle, title) || differs(pagePassage, passage) || differs(pageDate, date)) {
      groups.push([index]);
      [title, passage, date] = [pageTitle, pagePassage, pageDate];
    } else {
      groups[groups.length - 1].push(index);
      title ??= pageTitle;
      passage ??= pagePassage;
      date ??= pageDate;
    }
  });
  return groups;
};

/** Each pair of neighbouring pages is right when both groupings agree on whether they share a sermon. */
export const scoreGrouping = (groups: number[][], truth: number[][]) => {
  const groupOf = (gs: number[][]) => new Map(gs.flatMap((g, gi) => g.map((p) => [p, gi] as const)));
  const got = groupOf(groups);
  const want = groupOf(truth);
  const pages = [...want.keys()].sort((a, b) => a - b);
  let correct = 0;
  for (let i = 1; i < pages.length; i += 1) {
    const same = (m: Map<number, number>) => m.get(pages[i]) === m.get(pages[i - 1]);
    if (same(got) === same(want)) correct += 1;
  }
  const total = Math.max(pages.length - 1, 0);
  return { correct, total, pass: correct === total && got.size === want.size };
};
