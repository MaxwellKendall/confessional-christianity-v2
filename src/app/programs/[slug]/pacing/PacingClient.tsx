'use client';

// Catechism pacing (mockup 2e, PRD §5.4): the household's controls —
// new questions per session, review depth, what counts as mastered, sessions
// per week, whether scripture shows every time. Defaults are sane; nothing
// is locked. Changes apply to the next session.
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { useEffect, useState } from 'react';

import { useChildren } from '@/hooks/useChildren';
import { useProgramState } from '@/hooks/useProgramState';
import { getActiveChildId } from '@/lib/activeChild';
import { getProgram, type PacingConfig } from '@/lib/programs';

function Stepper({
  label, value, min, max, onChange,
}: {
  label: string;
  value: number;
  min: number;
  max: number;
  onChange: (next: number) => void;
}) {
  return (
    <div className="flex items-center justify-between border-t border-hairline py-3.5 first:border-t-0 first:pt-0">
      <span className="font-display text-[12.5px] tracking-[0.02em]">{label}</span>
      <div className="flex items-center gap-3.5 font-display text-[13px]">
        <button
          type="button"
          aria-label={`Decrease ${label.toLowerCase()}`}
          disabled={value <= min}
          onClick={() => onChange(Math.max(min, value - 1))}
          className={`cursor-pointer border-none bg-transparent font-display text-[13px] ${value <= min ? 'text-muted' : 'text-ink'}`}
        >
          −
        </button>
        <span className="min-w-3.5 text-center">{value}</span>
        <button
          type="button"
          aria-label={`Increase ${label.toLowerCase()}`}
          disabled={value >= max}
          onClick={() => onChange(Math.min(max, value + 1))}
          className={`cursor-pointer border-none bg-transparent font-display text-[13px] ${value >= max ? 'text-muted' : 'text-ink'}`}
        >
          +
        </button>
      </div>
    </div>
  );
}

function RadioGroup<T extends string>({
  legend, options, value, onChange,
}: {
  legend: string;
  options: { value: T; label: string }[];
  value: T;
  onChange: (next: T) => void;
}) {
  return (
    <fieldset className="m-0 border-none p-0">
      <legend className="label-caps mb-3 p-0 text-[9.5px] tracking-[0.1em] text-ink-3">
        {legend}
      </legend>
      <div className="flex flex-col gap-2.5">
        {options.map((option) => {
          const selected = option.value === value;
          return (
            <button
              key={option.value}
              type="button"
              role="radio"
              aria-checked={selected}
              onClick={() => onChange(option.value)}
              className={`flex cursor-pointer items-baseline gap-2.5 border-none bg-transparent p-0 text-left font-body text-[13px] ${selected ? 'font-semibold text-ink' : 'text-ink-3'}`}
            >
              <span className="text-[11px]" aria-hidden="true">{selected ? '◉' : '○'}</span>
              {option.label}
            </button>
          );
        })}
      </div>
    </fieldset>
  );
}

export function PacingClient({ slug }: { slug: string }) {
  const program = getProgram(slug)!;
  const { children } = useChildren();
  const [activeId, setActiveId] = useState<string | null>(null);

  useEffect(() => {
    if (!children.length) return;
    const stored = getActiveChildId();
    setActiveId(children.some((c) => c.id === stored) ? stored : children[0].id);
  }, [children]);

  const child = children.find((c) => c.id === activeId) ?? null;
  const { assignment, pacing, savePacing, loading } = useProgramState(program, child);

  const [draft, setDraft] = useState<PacingConfig | null>(null);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const router = useRouter();

  useEffect(() => {
    if (!loading) setDraft(pacing);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [loading]);

  if (!draft) return <div className="min-h-64" aria-hidden="true" />;

  if (!child || !assignment) {
    return (
      <div className="px-9 pt-14 text-center">
        <h1 className="mb-2.5 font-display text-[19px] font-semibold">No Saved Progress Yet</h1>
        <p className="text-[13px] italic leading-relaxed text-ink-2">
          <Link href={`/programs/${slug}`} className="dotted-link text-ink">
            Begin the catechism
          </Link>
          {' '}for a child before changing pacing.
        </p>
      </div>
    );
  }

  const onSave = async () => {
    setSaving(true);
    setError(null);
    try {
      await savePacing(draft);
      router.push(`/programs/${slug}`);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Could not save');
      setSaving(false);
    }
  };

  return (
    <div className="pb-6">
      <div className="border-b border-hairline px-5 pt-4 pb-3 text-center label-caps text-[9.5px] tracking-[0.1em]">
        <Link href={`/programs/${slug}`} className="dotted-link text-ink-3">
          {program.title}
        </Link>
      </div>

      <div className="px-6 pt-4 text-center">
        <h1 className="mb-2 font-display text-[19px] font-semibold">How This Catechism Is Paced</h1>
        <div className="label-caps mb-2.5 text-[9.5px] tracking-[0.1em] text-ink-3">
          Adjusting for: {child.name}
        </div>
        <p className="m-0 text-[12.5px] italic leading-relaxed text-ink-2">
          A default pace is set for you — slow enough to let a child dwell, not
          just recite. Adjust anything below; changes apply to your next session.
        </p>
      </div>

      <div className="mx-5 mt-6 border-t border-hairline pt-4">
        <Stepper
          label="New questions per session"
          value={draft.newQuestionsPerSession}
          min={1}
          max={10}
          onChange={(v) => setDraft({ ...draft, newQuestionsPerSession: v })}
        />
        <Stepper
          label="Sessions per week"
          value={draft.sessionsPerWeek}
          min={1}
          max={7}
          onChange={(v) => setDraft({ ...draft, sessionsPerWeek: v })}
        />
      </div>

      <div className="mx-5 mt-5 border-t border-hairline pt-4">
        <RadioGroup
          legend="Review each session"
          value={draft.reviewDepth}
          onChange={(v) => setDraft({ ...draft, reviewDepth: v })}
          options={[
            { value: 'recent', label: 'Last 5 learned' },
            { value: 'rotation', label: 'All learned so far, rotating' },
            { value: 'weak_only', label: 'Only what’s still shaky' },
          ]}
        />
      </div>

      <div className="mx-5 mt-5 border-t border-hairline pt-4">
        <RadioGroup
          legend="Consider a question mastered when—"
          value={draft.masteryRule}
          onChange={(v) => setDraft({ ...draft, masteryRule: v })}
          options={[
            { value: 'streak', label: 'Recited unprompted, 3 sessions running' },
            { value: 'manual', label: 'I’ll mark it myself, anytime' },
            { value: 'exposures', label: 'After 6 exposures, regardless' },
          ]}
        />
      </div>

      <div className="mx-5 mt-5 border-t border-hairline pt-4">
        <div className="flex items-center justify-between">
          <span className="font-display text-[12.5px] tracking-[0.02em]">
            Include underlying scripture each time
          </span>
          <button
            type="button"
            role="switch"
            aria-checked={draft.showScriptureEveryTime}
            onClick={() => setDraft({
              ...draft,
              showScriptureEveryTime: !draft.showScriptureEveryTime,
            })}
            className={`label-caps cursor-pointer rounded-[10px] border border-solid bg-transparent px-2.5 py-[3px] text-[9.5px] tracking-[0.1em] ${draft.showScriptureEveryTime ? 'border-ink text-ink' : 'border-muted text-ink-3'}`}
          >
            {draft.showScriptureEveryTime ? 'On' : 'Off'}
          </button>
        </div>
      </div>

      {error && (
        <p className="mt-4 px-6 text-center text-[12.5px] italic text-ink-2" role="alert">{error}</p>
      )}

      <div className="mx-5 mt-6 border-t border-hairline pt-4">
        <button
          type="button"
          disabled={saving}
          onClick={onSave}
          className="action-button w-full cursor-pointer bg-transparent"
        >
          {saving ? 'Saving…' : 'Save Pacing'}
        </button>
      </div>
    </div>
  );
}
