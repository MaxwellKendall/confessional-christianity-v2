'use client';

// Reading-plan progress: which days of each plan this device has read. Its
// own store beside localWorship, localCatechismProgress, and
// localSeriesProgress — a plan's days are computed chapters (see
// readingPlanContent.ts), not authored devotions, so it's a sibling domain
// rather than a borrowed corner of the series store. Only completions are
// stored; the current day is derived at read time as the first day without
// one, same as series progress.
const STORAGE_KEY = 'cc.localReadingPlanProgress.v1';

export type ReadingPlanCompletions = Record<string, number[]>;

interface LocalReadingPlanProgress {
  version: 1;
  completions: ReadingPlanCompletions;
}

const emptyStore = (): LocalReadingPlanProgress => ({ version: 1, completions: {} });

const migrateStoredShape = (parsed: unknown): LocalReadingPlanProgress | null => {
  if (!parsed || typeof parsed !== 'object') return null;
  const candidate = parsed as Partial<LocalReadingPlanProgress>;
  if (candidate.version !== 1) return null;
  return { version: 1, completions: candidate.completions ?? {} };
};

const canUseStorage = () => typeof window !== 'undefined' && Boolean(window.localStorage);

const readStore = (): LocalReadingPlanProgress => {
  if (!canUseStorage()) return emptyStore();
  try {
    const raw = window.localStorage.getItem(STORAGE_KEY);
    if (!raw) return emptyStore();
    return migrateStoredShape(JSON.parse(raw)) ?? emptyStore();
  } catch {
    return emptyStore();
  }
};

const writeStore = (store: LocalReadingPlanProgress) => {
  if (!canUseStorage()) return;
  window.localStorage.setItem(STORAGE_KEY, JSON.stringify(store));
};

/** Idempotent, like recordSeriesPartCompletion — replaying a read day
 * changes nothing, and progress never regresses. */
export const recordReadingPlanDayRead = (planSlug: string, day: number): void => {
  const store = readStore();
  const days = store.completions[planSlug] ?? [];
  if (days.includes(day)) return;
  store.completions[planSlug] = [...days, day];
  writeStore(store);
};

export const getReadingPlanCompletedDays = (planSlug: string): number[] => (
  readStore().completions[planSlug] ?? []
);
