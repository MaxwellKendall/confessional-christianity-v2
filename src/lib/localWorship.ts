'use client';

// Worship completions: which services (morning/evening, by local calendar
// day) this device has finished. Its own store beside — never inside —
// localCatechismProgress: the worship streak sits alongside the question
// milestones (mockup 11j), it doesn't replace them. The streak is derived at
// read time, not stored.
import type { Daypart } from './worship';

const STORAGE_KEY = 'cc.localWorship.v1';

export type WorshipCompletions = Record<string, Partial<Record<Daypart, boolean>>>;

interface LocalWorship {
  version: 1;
  completions: WorshipCompletions;
}

const emptyStore = (): LocalWorship => ({ version: 1, completions: {} });

const migrateStoredShape = (parsed: unknown): LocalWorship | null => {
  if (!parsed || typeof parsed !== 'object') return null;
  const candidate = parsed as Partial<LocalWorship>;
  if (candidate.version !== 1) return null;
  return { version: 1, completions: candidate.completions ?? {} };
};

/** YYYY-MM-DD from local date components — the household's own calendar day,
 * consistent with everything else on this device being device-local. */
export const localDateKey = (date: Date): string => [
  String(date.getFullYear()),
  String(date.getMonth() + 1).padStart(2, '0'),
  String(date.getDate()).padStart(2, '0'),
].join('-');

const previousDateKey = (key: string): string => {
  const [y, m, d] = key.split('-').map(Number);
  return localDateKey(new Date(y, m - 1, d - 1));
};

const isCompletedDay = (completions: WorshipCompletions, key: string): boolean => Boolean(
  completions[key]?.morning || completions[key]?.evening,
);

// Consecutive days with at least one completed service, counting back from
// today — or from yesterday when today's service simply hasn't happened yet
// (a streak isn't broken until the day is actually missed). One service a
// day sustains it; 11j shows the morning alone incrementing 14 → 15.
export const computeStreak = (completions: WorshipCompletions, todayKey: string): number => {
  let day = isCompletedDay(completions, todayKey) ? todayKey : previousDateKey(todayKey);
  let streak = 0;
  while (isCompletedDay(completions, day)) {
    streak += 1;
    day = previousDateKey(day);
  }
  return streak;
};

const canUseStorage = () => typeof window !== 'undefined' && Boolean(window.localStorage);

const readStore = (): LocalWorship => {
  if (!canUseStorage()) return emptyStore();
  try {
    const raw = window.localStorage.getItem(STORAGE_KEY);
    if (!raw) return emptyStore();
    return migrateStoredShape(JSON.parse(raw)) ?? emptyStore();
  } catch {
    return emptyStore();
  }
};

const writeStore = (store: LocalWorship) => {
  if (!canUseStorage()) return;
  window.localStorage.setItem(STORAGE_KEY, JSON.stringify(store));
};

export const recordWorshipCompletion = (daypart: Daypart, date = new Date()): void => {
  const store = readStore();
  const key = localDateKey(date);
  store.completions[key] = { ...store.completions[key], [daypart]: true };
  writeStore(store);
};

export const getWorshipCompletion = (
  date = new Date(),
): Partial<Record<Daypart, boolean>> => readStore().completions[localDateKey(date)] ?? {};

export const getWorshipStreak = (date = new Date()): number => (
  computeStreak(readStore().completions, localDateKey(date))
);
