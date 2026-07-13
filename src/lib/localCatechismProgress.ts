'use client';

// Guest progress: a visitor's chosen catechism and per-question milestones
// persist in localStorage, keyed by catechism. No account, no name capture —
// this is the only progress store the app has.
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
  tracks: Record<string, LocalCatechismTrack>;
}

const emptyProgress = (): LocalCatechismProgress => ({
  version: 2,
  activeCatechismId: null,
  tracks: {},
});

// Accepts whatever JSON is in storage and returns a current-shape store, or
// null when it's unrecognizable. Older stores (versions 1-2) also carried a
// learner name/age; those fields are simply dropped on read.
export const migrateStoredShape = (parsed: unknown): LocalCatechismProgress | null => {
  if (!parsed || typeof parsed !== 'object') return null;
  const candidate = parsed as Partial<Omit<LocalCatechismProgress, 'version'>> & { version?: number };
  if (candidate.version !== 1 && candidate.version !== 2) return null;
  return {
    version: 2,
    activeCatechismId: candidate.activeCatechismId ?? null,
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

// Jumping to an arbitrary question (e.g. "go back to Q1") repositions the
// track without touching milestones — it's browsing, not re-introducing
// material, so it shouldn't mark anything as freshly "introduced".
export const jumpToLocalQuestion = (
  catechismId: string,
  questionNumber: number,
  totalQuestions: number,
): LocalCatechismTrack | null => {
  const progress = readProgress();
  const existing = progress.tracks[catechismId];
  if (!existing) return null;
  const clamped = Math.min(totalQuestions, Math.max(1, questionNumber));
  const track: LocalCatechismTrack = {
    ...existing,
    currentQuestion: clamped,
    updatedAt: new Date().toISOString(),
  };
  progress.activeCatechismId = catechismId;
  progress.tracks[catechismId] = track;
  writeProgress(progress);
  return track;
};

export const localProgressLabel = 'Saved on this device';
