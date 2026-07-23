'use client';

// Series progress: which parts of each devotion series this device has
// finished. Its own store beside localWorship and localCatechismProgress,
// same as those two sit beside each other. Only completions are stored;
// the current part is derived at read time as the first day without one —
// the sequence, not the calendar, sets the pace (turn 16), so there are no
// dates in here at all.
const STORAGE_KEY = 'cc.localSeriesProgress.v1';

/** Completed part days per series slug, in the order they were finished. */
export type SeriesCompletions = Record<string, number[]>;

interface LocalSeriesProgress {
  version: 1;
  completions: SeriesCompletions;
}

const emptyStore = (): LocalSeriesProgress => ({ version: 1, completions: {} });

const migrateStoredShape = (parsed: unknown): LocalSeriesProgress | null => {
  if (!parsed || typeof parsed !== 'object') return null;
  const candidate = parsed as Partial<LocalSeriesProgress>;
  if (candidate.version !== 1) return null;
  return { version: 1, completions: candidate.completions ?? {} };
};

/** The part Continue should jump to: the first of the series' days without a
 * completion. A suggestion, not a gate — every authored part stays reachable
 * regardless of this value. Null once every part is complete. */
export const currentPartDay = (
  completedDays: readonly number[],
  totalParts: number,
): number | null => {
  const done = new Set(completedDays);
  for (let day = 1; day <= totalParts; day += 1) {
    if (!done.has(day)) return day;
  }
  return null;
};

const canUseStorage = () => typeof window !== 'undefined' && Boolean(window.localStorage);

const readStore = (): LocalSeriesProgress => {
  if (!canUseStorage()) return emptyStore();
  try {
    const raw = window.localStorage.getItem(STORAGE_KEY);
    if (!raw) return emptyStore();
    return migrateStoredShape(JSON.parse(raw)) ?? emptyStore();
  } catch {
    return emptyStore();
  }
};

const writeStore = (store: LocalSeriesProgress) => {
  if (!canUseStorage()) return;
  window.localStorage.setItem(STORAGE_KEY, JSON.stringify(store));
};

/** Idempotent, like recordWorshipCompletion — replaying a finished part
 * changes nothing, and progress never regresses. */
export const recordSeriesPartCompletion = (seriesSlug: string, day: number): void => {
  const store = readStore();
  const days = store.completions[seriesSlug] ?? [];
  if (days.includes(day)) return;
  store.completions[seriesSlug] = [...days, day];
  writeStore(store);
};

export const getSeriesCompletedDays = (seriesSlug: string): number[] => (
  readStore().completions[seriesSlug] ?? []
);
