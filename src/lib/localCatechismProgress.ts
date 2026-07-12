'use client';

// Guest/pre-account progress (handoff turn 7, PRD "Anonymous Local Progress"):
// a signed-out visitor's learner, chosen catechism, and per-question milestones
// persist in localStorage so declining the save gate never loses their place.
// The pure track/shape helpers are exported for tests; the storage wrappers
// stay thin.
const STORAGE_KEY = 'cc.localCatechismProgress.v1';

export interface LocalMilestone {
  state: 'introduced' | 'reviewing' | 'mastered';
  introducedAt: string;
  reviewCount: number;
}

export interface LocalCatechismTrack {
  catechismId: string;
  currentQuestion: number;
  startedAtQuestion: number;
  startedAt: string;
  updatedAt: string;
  milestones: Record<string, LocalMilestone>;
}

export interface LocalCatechismProgress {
  version: 2;
  activeCatechismId: string | null;
  learnerName: string;
  learnerAge: number | null;
  tracks: Record<string, LocalCatechismTrack>;
}

export const DEFAULT_LEARNER_NAME = 'My child';

const emptyProgress = (): LocalCatechismProgress => ({
  version: 2,
  activeCatechismId: null,
  learnerName: DEFAULT_LEARNER_NAME,
  learnerAge: null,
  tracks: {},
});

// Accepts whatever JSON is in storage and returns a current-shape store, or
// null when it's unrecognizable. v1 lacked learnerAge; the key stays the same
// so other tabs keep reading the store they know.
export const migrateStoredShape = (parsed: unknown): LocalCatechismProgress | null => {
  if (!parsed || typeof parsed !== 'object') return null;
  const candidate = parsed as Partial<Omit<LocalCatechismProgress, 'version'>> & { version?: number };
  if (candidate.version !== 1 && candidate.version !== 2) return null;
  return {
    version: 2,
    activeCatechismId: candidate.activeCatechismId ?? null,
    learnerName: candidate.learnerName ?? DEFAULT_LEARNER_NAME,
    learnerAge: candidate.learnerAge ?? null,
    tracks: candidate.tracks ?? {},
  };
};

// The 7c "Next Question" primitive: the current question enters the record as
// introduced and the position advances, clamped one past the end so a
// finished track reads as complete.
export const advanceTrack = (
  track: LocalCatechismTrack,
  totalQuestions: number,
  now = new Date().toISOString(),
): LocalCatechismTrack => {
  const key = String(track.currentQuestion);
  const milestones = track.currentQuestion <= totalQuestions && !track.milestones[key]
    ? {
      ...track.milestones,
      [key]: { state: 'introduced' as const, introducedAt: now, reviewCount: 0 },
    }
    : track.milestones;
  return {
    ...track,
    currentQuestion: Math.min(totalQuestions + 1, track.currentQuestion + 1),
    milestones,
    updatedAt: now,
  };
};

const canUseStorage = () => typeof window !== 'undefined' && Boolean(window.localStorage);

const readProgress = (): LocalCatechismProgress => {
  if (!canUseStorage()) return emptyProgress();
  try {
    const raw = window.localStorage.getItem(STORAGE_KEY);
    if (!raw) return emptyProgress();
    return migrateStoredShape(JSON.parse(raw)) ?? emptyProgress();
  } catch {
    return emptyProgress();
  }
};

const writeProgress = (progress: LocalCatechismProgress) => {
  if (!canUseStorage()) return;
  window.localStorage.setItem(STORAGE_KEY, JSON.stringify(progress));
};

export const getLocalCatechismTrack = (catechismId: string): LocalCatechismTrack | null => (
  readProgress().tracks[catechismId] ?? null
);

export const getLocalLearner = (): { name: string; age: number | null } => {
  const progress = readProgress();
  return { name: progress.learnerName, age: progress.learnerAge };
};

export const setLocalLearner = (name: string, age: number | null) => {
  const progress = readProgress();
  progress.learnerName = name.trim() || DEFAULT_LEARNER_NAME;
  progress.learnerAge = age;
  writeProgress(progress);
};

export const startLocalCatechismTrack = (
  catechismId: string,
  startingQuestion: number,
): LocalCatechismTrack => {
  const progress = readProgress();
  const now = new Date().toISOString();
  const track: LocalCatechismTrack = {
    catechismId,
    currentQuestion: startingQuestion,
    startedAtQuestion: startingQuestion,
    startedAt: now,
    updatedAt: now,
    milestones: {},
  };
  progress.activeCatechismId = catechismId;
  progress.tracks[catechismId] = track;
  writeProgress(progress);
  return track;
};

export const advanceLocalQuestion = (
  catechismId: string,
  totalQuestions: number,
): LocalCatechismTrack | null => {
  const progress = readProgress();
  const existing = progress.tracks[catechismId];
  if (!existing) return null;
  const track = advanceTrack(existing, totalQuestions);
  progress.activeCatechismId = catechismId;
  progress.tracks[catechismId] = track;
  writeProgress(progress);
  return track;
};

// Migration snapshot: everything the claim step needs to turn this device's
// guest progress into a real child record.
export const getLocalProgressSnapshot = (): {
  learnerName: string;
  learnerAge: number | null;
  track: LocalCatechismTrack | null;
} => {
  const progress = readProgress();
  const track = progress.activeCatechismId
    ? progress.tracks[progress.activeCatechismId] ?? null
    : null;
  return { learnerName: progress.learnerName, learnerAge: progress.learnerAge, track };
};

// Called only after a successful claim; failure paths must leave the store
// untouched so the guest can retry.
export const clearLocalCatechismProgress = () => {
  if (!canUseStorage()) return;
  window.localStorage.removeItem(STORAGE_KEY);
};

export const localProgressLabel = 'Saved on this device';
