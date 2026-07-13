'use client';

// Claiming guest progress (handoff turn 7, PRD "Conversion"): when an account
// appears on a device that has a local track, that track becomes a real child
// record — child, assignment, mastery — and only then is the local store
// cleared. Any failure leaves the store untouched so the next auth event
// retries. The row-building is pure so it can be pinned by tests.
import type { SupabaseClient } from '@supabase/supabase-js';

import { setActiveChildId } from './activeChild';
import {
  clearLocalCatechismProgress,
  getLocalProgressSnapshot,
  type LocalCatechismTrack,
} from './localCatechismProgress';
import type { CatechismAssignmentRow, ChildRow } from './database.types';

export interface ClaimRows {
  assignment: { catechism_id: string; current_question: number };
  mastery: {
    question_number: number;
    state: 'reviewing' | 'mastered';
    recited_streak: 0;
    exposures: number;
    last_reviewed_at: string;
  }[];
}

// Mirrors how the guest session already projected milestones onto mastery
// rows: mastered carries over, everything else enters as reviewing with at
// least one exposure.
export const buildClaimRows = (track: LocalCatechismTrack): ClaimRows => ({
  assignment: {
    catechism_id: track.catechismId,
    current_question: track.currentQuestion,
  },
  mastery: Object.entries(track.milestones)
    .map(([questionNumber, milestone]) => ({
      question_number: Number(questionNumber),
      state: milestone.state === 'mastered' ? 'mastered' as const : 'reviewing' as const,
      recited_streak: 0 as const,
      exposures: Math.max(1, milestone.reviewCount + 1),
      last_reviewed_at: milestone.introducedAt,
    }))
    .sort((a, b) => a.question_number - b.question_number),
});

interface ClaimJoinRow {
  child: (ChildRow & { catechism_assignments: CatechismAssignmentRow[] }) | null;
}

export type ClaimResult = 'claimed' | 'skipped' | 'nothing-to-claim';

/** Fired on window after a successful claim so mounted children lists refetch. */
export const LOCAL_PROGRESS_CLAIMED_EVENT = 'cc:local-progress-claimed';

export const claimLocalProgress = async (
  supabase: SupabaseClient,
  userId: string,
): Promise<ClaimResult> => {
  const { learnerName, learnerAge, track } = getLocalProgressSnapshot();
  if (!track) return 'nothing-to-claim';

  const fetchChildren = async () => {
    const { data, error } = await supabase
      .from('user_children')
      .select('child:children (*, catechism_assignments (*))')
      .eq('user_id', userId);
    if (error) throw error;
    return ((data ?? []) as unknown as ClaimJoinRow[])
      .map((row) => row.child)
      .filter((child): child is NonNullable<ClaimJoinRow['child']> => Boolean(child));
  };

  // Dedupe guard: a same-named child already running this catechism means
  // this device's track was almost certainly already claimed — don't create
  // a duplicate child on a retry or a second sign-in.
  const existing = await fetchChildren();
  const alreadyClaimed = existing.find((child) => (
    child.name === learnerName
    && child.catechism_assignments.some((a) => a.catechism_id === track.catechismId)
  ));
  if (alreadyClaimed) {
    setActiveChildId(alreadyClaimed.id);
    clearLocalCatechismProgress();
    return 'skipped';
  }

  const rows = buildClaimRows(track);

  // Insert without .select(): the children SELECT policy checks
  // user_children, which the auto_add_child_owner trigger populates after
  // insert (same pattern as useChildren.addChild). Re-query to find the row.
  const { error: childError } = await supabase
    .from('children')
    .insert({ user_id: userId, name: learnerName, age: learnerAge });
  if (childError) throw childError;

  const child = (await fetchChildren())
    .filter((c) => c.name === learnerName)
    .sort((a, b) => b.created_at.localeCompare(a.created_at))[0];
  if (!child) throw new Error('Claim failed: created child not readable');

  const { data: assignmentData, error: assignmentError } = await supabase
    .from('catechism_assignments')
    .insert({ child_id: child.id, ...rows.assignment })
    .select()
    .single();
  if (assignmentError) throw assignmentError;
  const assignment = assignmentData as CatechismAssignmentRow;

  if (rows.mastery.length) {
    const { error: masteryError } = await supabase
      .from('question_mastery')
      .upsert(
        rows.mastery.map((m) => ({ assignment_id: assignment.id, ...m })),
        { onConflict: 'assignment_id,question_number' },
      );
    if (masteryError) throw masteryError;
  }

  setActiveChildId(child.id);
  clearLocalCatechismProgress();
  return 'claimed';
};
