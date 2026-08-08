'use client';

// A reading plan's home (mockup 19c, simplified): a calendar grid of
// read/unread days replaces the catechism's mastery heart — reading
// progress is read/not-read per day, no streak count, and no Bible text
// rendered here — just the day's reading prompt (citation) and a mark-done
// action, since the plan is tracking that the reading happened, not hosting
// the reading itself. Tracked for the current reader only, no per-child
// ownership. Every day is reachable directly from the grid — tapping ahead
// marks that day done outright, the plan's "skip ahead" — same "nothing is
// locked" rule as a devotion series (SeriesLandingClient).
import { useEffect, useState } from 'react';

import { getReadingPlanCompletedDays, recordReadingPlanDayRead } from '@/lib/localReadingPlanProgress';
import { currentPartDay } from '@/lib/localSeriesProgress';
import { getReadingPlanDay } from '@/lib/readingPlanContent';
import type { ReadingPlanDefinition } from '@/lib/readingPlans';

export function ReadingPlanClient({ plan }: { plan: ReadingPlanDefinition }) {
  const [completed, setCompleted] = useState<number[] | null>(null);
  useEffect(() => {
    setCompleted(getReadingPlanCompletedDays(plan.slug));
  }, [plan.slug]);

  if (!completed) {
    return <div className="min-h-64" aria-hidden="true" />;
  }

  const done = new Set(completed);
  const current = currentPartDay(completed, plan.totalDays) ?? plan.totalDays;
  const today = getReadingPlanDay(plan, current);
  const progressPct = Math.round((done.size / plan.totalDays) * 100);
  const allDone = currentPartDay(completed, plan.totalDays) === null;

  const markDay = (day: number) => {
    recordReadingPlanDayRead(plan.slug, day);
    setCompleted((prev) => (prev?.includes(day) ? prev : [...(prev ?? []), day]));
  };

  return (
    <div className="pb-12">
      <div className="px-6 pt-7 pb-4 text-center">
        <div className="label-caps mb-2.5 text-[9px] tracking-[0.14em] text-ochre">
          {plan.pace} · Reading Plan
        </div>
        <h1 className="m-0 mb-2.5 heading-page">{plan.title}</h1>
        <p className="m-0 mb-5.5 font-body text-[13px] italic leading-[1.7] text-ink-2">
          {plan.description}
        </p>

        <div className="label-caps mb-2 text-[10px] tracking-[0.12em] text-ink-3">
          {allDone ? `All ${plan.totalDays} days read` : `Day ${current} of ${plan.totalDays}`}
        </div>
        <div className="mx-auto mb-5.5 h-[3px] w-full bg-hairline" aria-hidden="true">
          <div className="h-full bg-ochre" style={{ width: `${progressPct}%` }} />
        </div>
      </div>

      {!allDone && today && (
        <div className="px-6 pb-6 text-center">
          <div className="mb-2.5 font-body text-[13px] italic text-ink-2">
            Today&rsquo;s reading:
            {' '}
            <span className="font-semibold not-italic text-ink">{today.citation}</span>
          </div>
          <button type="button" onClick={() => markDay(current)} className="action-button block w-full">
            Mark as Done
          </button>
        </div>
      )}

      <div className="px-6">
        <div className="label-caps mb-2.5 flex items-baseline justify-between text-[9px] tracking-[0.1em] text-ink-3">
          <span>Reading Progress</span>
          <span className="font-body text-[11px] italic normal-case tracking-normal text-ink-3">
            Tap a day to mark it done
          </span>
        </div>
        <div className="grid grid-cols-7 gap-1.5 pb-4">
          {Array.from({ length: plan.totalDays }, (_, i) => i + 1).map((day) => {
            const isDone = done.has(day);
            const isCurrent = !allDone && day === current;
            return (
              <button
                key={day}
                type="button"
                onClick={() => markDay(day)}
                disabled={isDone}
                aria-label={`Day ${day}${isDone ? ', read' : ', mark as read'}`}
                className={`flex aspect-square items-center justify-center rounded-sm border font-display text-[9.5px] ${
                  isDone
                    ? 'border-ochre bg-ochre text-card'
                    : isCurrent
                      ? 'border-ochre bg-transparent text-ochre'
                      : 'border-transparent bg-fill text-ink-3'
                }`}
              >
                {day}
              </button>
            );
          })}
        </div>
      </div>
    </div>
  );
}
