// Age-labeled checkpoints (mockup 9a, turn 9): the replacement for the old
// pacing/session-plan wizard. There's no schedule — a milestone's progress
// is derived purely from how far a track's position has advanced, so it
// needs no DB read beyond what the caller already has.
export interface MilestoneDefinition {
  id: string;
  title: string;
  /** inclusive question-number range this milestone covers */
  range: [number, number];
  /** editorial guidance only, e.g. "typical for age 7–8" — not compared
   * against the child's actual age */
  typicalAge?: [number, number];
}

// Authored per program slug, same pattern as prayers (content/programs/<slug>).
// Only WSC has real milestones so far; other programs render the honest
// "not yet mapped" empty state until someone authors theirs.
const MILESTONES: Record<string, MilestoneDefinition[]> = {
  'catechizing-shorter-catechism': [
    { id: 'first-ten', title: 'First Ten Questions', range: [1, 10] },
    {
      id: 'ten-commandments', title: 'The Ten Commandments', range: [42, 81], typicalAge: [7, 8],
    },
    {
      id: 'halfway', title: 'Half the Catechism', range: [1, 54], typicalAge: [9, 10],
    },
    {
      id: 'complete', title: 'The Whole Catechism', range: [1, 107], typicalAge: [11, 12],
    },
  ],
};

export const milestonesFor = (slug: string): MilestoneDefinition[] => MILESTONES[slug] ?? [];

export interface MilestoneProgress extends MilestoneDefinition {
  seenCount: number;
  total: number;
  state: 'complete' | 'in_progress' | 'locked';
}

// `currentQuestion` is a 1-indexed position pointer (as used throughout the
// programs/localCatechismProgress domains): every question number below it
// has been seen.
export const milestoneProgress = (
  definitions: MilestoneDefinition[],
  currentQuestion: number,
): MilestoneProgress[] => definitions.map((def) => {
  const [start, end] = def.range;
  const total = end - start + 1;
  const seenCount = Math.min(total, Math.max(0, currentQuestion - start));
  const state: MilestoneProgress['state'] = seenCount >= total
    ? 'complete'
    : seenCount > 0 ? 'in_progress' : 'locked';
  return {
    ...def, total, seenCount, state,
  };
});
