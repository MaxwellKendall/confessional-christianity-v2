// Topical checkpoints (turn 18, replacing the age-labeled version from
// mockup 9a): age-banded, overlapping ranges ("Half the Catechism" at
// 9–10, "The Ten Commandments" at 7–8) didn't correspond to anything in
// the catechism itself, so nobody used them. A milestone now names one of
// the catechism's own doctrinal divisions, in the order the catechism
// teaches them — there's no schedule here either; progress is still
// derived purely from how far a track's position has advanced.
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
//
// Ranges follow the catechism's own doctrinal structure, not an external
// pacing scheme: Scripture (1–3), God (4–8), Creation & Providence (9–11),
// the Fall (12–20), the Person of Christ (21–28), salvation applied —
// effectual calling through justification, adoption, and sanctification
// (29–38), the Ten Commandments (39–84, which also carries the preface to
// the law and sin's demerit), faith & repentance (85–87), the means of
// grace — Word and sacraments (88–97), and prayer (98–107). Every question
// falls in exactly one range, in catechism order.
const MILESTONES: Record<string, MilestoneDefinition[]> = {
  'catechizing-shorter-catechism': [
    { id: 'scripture', title: 'Scripture', range: [1, 3] },
    { id: 'god', title: 'God', range: [4, 8] },
    { id: 'creation-providence', title: 'Creation & Providence', range: [9, 11] },
    { id: 'the-fall', title: 'The Fall', range: [12, 20] },
    { id: 'person-of-christ', title: 'The Person of Christ', range: [21, 28] },
    { id: 'salvation-applied', title: 'Salvation Applied', range: [29, 38] },
    { id: 'ten-commandments', title: 'The Ten Commandments', range: [39, 84] },
    { id: 'faith-repentance', title: 'Faith & Repentance', range: [85, 87] },
    { id: 'means-of-grace', title: 'The Means of Grace', range: [88, 97] },
    { id: 'prayer', title: 'Prayer', range: [98, 107] },
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
