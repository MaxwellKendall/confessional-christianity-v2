'use client';

// The devotion editor: the wrapper metadata (title, summary, description,
// grounding), the series part it fills, and the eight fixed steps with their
// typed elements. The eight roles are fixed — the worship shell renders by
// position — so authors fill steps rather than arrange them. Validation is
// the same function the server runs before saving, shown live here.
import Link from 'next/link';
import { useMemo, useState, useTransition } from 'react';

import { blankElement, type ElementType } from '@/lib/admin/devotionDraft';
import { citationToOsis } from '@/lib/bible';
import type { Devotion, DevotionGrounding } from '@/lib/devotions';
import { SEASONS, TOPICS } from '@/lib/devotions';
import type { DevotionSeries } from '@/lib/devotionSeries';
import {
  ELEMENT_TYPES, findSeriesLink, validateDevotion, type SeriesLink,
} from '@/lib/devotionValidation';
import type { WorshipElement } from '@/lib/worship';
import { lookupScripture, saveDevotion, type SaveResponse } from '../actions';
import { DraftStatus } from '../DraftStatus';

const ELEMENT_LABELS: Record<ElementType, string> = {
  scripture: 'Scripture',
  prayer: 'Prayer',
  song: 'Song',
  creed: 'Creed',
  catechism: 'Catechism question',
  instruction: 'Instruction',
  prompts: 'Prayer prompts',
};

const inputClass = 'w-full rounded-md border border-hairline bg-white px-2.5 py-1.5 font-body text-[14px] text-ink';
const textareaClass = `${inputClass} min-h-[5.5rem] leading-relaxed`;

function Field({ label, hint, children }: { label: string; hint?: string; children: React.ReactNode }) {
  return (
    <label className="flex flex-col gap-1">
      <span className="label-caps text-[9.5px] text-ink-3">{label}</span>
      {children}
      {hint && <span className="text-[11.5px] text-ink-3">{hint}</span>}
    </label>
  );
}

function SmallButton(
  { children, onClick, disabled, title }: {
    children: React.ReactNode; onClick: () => void; disabled?: boolean; title?: string;
  },
) {
  return (
    <button
      type="button"
      onClick={onClick}
      disabled={disabled}
      title={title}
      className="rounded border border-hairline bg-card px-2 py-0.5 text-[12px] text-ink-2 hover:bg-fill disabled:opacity-40"
    >
      {children}
    </button>
  );
}

// ---------------------------------------------------------------------------

function GroundingFields(
  { grounding, onChange }: { grounding: DevotionGrounding; onChange: (g: DevotionGrounding) => void },
) {
  const switchKind = (kind: DevotionGrounding['kind']) => {
    switch (kind) {
      case 'scripture': return onChange({ kind, osis: '', citation: '' });
      case 'topic': return onChange({ kind, topic: TOPICS[0].slug });
      case 'catechism': return onChange({ kind, entryIds: [] });
      case 'season': return onChange({ kind, season: SEASONS[0].slug, day: 1 });
      default: return undefined;
    }
  };
  return (
    <div className="grid gap-3 sm:grid-cols-[12rem_1fr]">
      <Field label="Grounded in">
        <select
          className={inputClass}
          value={grounding.kind}
          onChange={(e) => switchKind(e.target.value as DevotionGrounding['kind'])}
        >
          <option value="scripture">Scripture</option>
          <option value="catechism">Confession &amp; catechism</option>
          <option value="topic">Topic</option>
          <option value="season">Season</option>
        </select>
      </Field>
      {grounding.kind === 'scripture' && (
        <div className="grid gap-3 sm:grid-cols-2">
          <Field label="Passage" hint="As readers see it, e.g. Psalm 130 or John 1:1–14">
            <input
              className={inputClass}
              value={grounding.citation}
              onChange={(e) => onChange({
                ...grounding,
                citation: e.target.value,
                osis: citationToOsis(e.target.value) ?? grounding.osis,
              })}
            />
          </Field>
          <Field label="OSIS" hint="Filled from the passage; edit only if it guessed wrong">
            <input
              className={`${inputClass} font-mono text-[13px]`}
              value={grounding.osis}
              onChange={(e) => onChange({ ...grounding, osis: e.target.value })}
            />
          </Field>
        </div>
      )}
      {grounding.kind === 'topic' && (
        <Field label="Topic">
          <select
            className={inputClass}
            value={grounding.topic}
            onChange={(e) => onChange({ ...grounding, topic: e.target.value })}
          >
            {TOPICS.map((t) => <option key={t.slug} value={t.slug}>{t.name}</option>)}
          </select>
        </Field>
      )}
      {grounding.kind === 'catechism' && (
        <Field label="Entry ids" hint="Comma-separated, consecutive questions from one document, e.g. WSC-51, WSC-52">
          <input
            className={`${inputClass} font-mono text-[13px]`}
            defaultValue={grounding.entryIds.join(', ')}
            onChange={(e) => onChange({
              ...grounding,
              entryIds: e.target.value.split(',').map((s) => s.trim()).filter(Boolean),
            })}
          />
        </Field>
      )}
      {grounding.kind === 'season' && (
        <div className="grid gap-3 sm:grid-cols-2">
          <Field label="Season">
            <select
              className={inputClass}
              value={grounding.season}
              onChange={(e) => onChange({ ...grounding, season: e.target.value })}
            >
              {SEASONS.map((s) => <option key={s.slug} value={s.slug}>{s.name}</option>)}
            </select>
          </Field>
          <Field label="Day">
            <input
              type="number"
              min={1}
              max={SEASONS.find((s) => s.slug === grounding.season)?.days}
              className={inputClass}
              value={grounding.day}
              onChange={(e) => onChange({ ...grounding, day: Number(e.target.value) })}
            />
          </Field>
        </div>
      )}
    </div>
  );
}

// ---------------------------------------------------------------------------

function SeriesFields(
  { series, slug, link, onChange }: {
    series: DevotionSeries[]; slug: string; link: SeriesLink | null; onChange: (l: SeriesLink | null) => void;
  },
) {
  const current = link ? series.find((s) => s.slug === link.seriesSlug) : null;
  return (
    <div className="grid gap-3 sm:grid-cols-[12rem_1fr]">
      <Field label="Series" hint={current ? undefined : 'Pick one to fill a part of it'}>
        <select
          className={inputClass}
          value={link?.seriesSlug ?? ''}
          onChange={(e) => {
            const next = series.find((s) => s.slug === e.target.value);
            if (!next) return onChange(null);
            const open = next.parts.find((p) => !p.devotionSlug || p.devotionSlug === slug);
            return onChange({ seriesSlug: next.slug, day: open?.day ?? 1 });
          }}
        >
          <option value="">Standalone (no series)</option>
          {series.map((s) => <option key={s.slug} value={s.slug}>{s.title}</option>)}
        </select>
      </Field>
      {current && link && (
        <Field label="Part" hint="Parts already filled by another devotion can't be picked">
          <select
            className={inputClass}
            value={link.day}
            onChange={(e) => onChange({ ...link, day: Number(e.target.value) })}
          >
            {current.parts.map((part) => {
              const taken = part.devotionSlug && part.devotionSlug !== slug;
              return (
                <option key={part.day} value={part.day} disabled={Boolean(taken)}>
                  {part.day}. {part.title} ({part.citation}){taken ? ` — ${part.devotionSlug}` : ''}
                </option>
              );
            })}
          </select>
          <Link href={`/admin/series/${current.slug}`} className="text-[11.5px] text-ink-3">
            Edit the {current.title} series ›
          </Link>
        </Field>
      )}
    </div>
  );
}

// ---------------------------------------------------------------------------

function ScriptureFields(
  { element, onChange }: {
    element: Extract<WorshipElement, { type: 'scripture' }>; onChange: (e: WorshipElement) => void;
  },
) {
  const [looking, startLookup] = useTransition();
  const [note, setNote] = useState<string | null>(null);
  const fetchText = () => startLookup(async () => {
    setNote(null);
    const found = await lookupScripture(element.citation);
    onChange({
      ...element,
      citation: found.osis ? found.citation : element.citation,
      osis: found.osis || element.osis,
      text: found.text ?? element.text,
    });
    if (found.error) setNote(found.error);
  });
  return (
    <>
      <div className="grid gap-3 sm:grid-cols-[1fr_1fr_auto] sm:items-end">
        <Field label="Citation">
          <input
            className={inputClass}
            value={element.citation}
            onChange={(e) => onChange({
              ...element,
              citation: e.target.value,
              osis: citationToOsis(e.target.value) ?? element.osis,
            })}
          />
        </Field>
        <Field label="OSIS">
          <input
            className={`${inputClass} font-mono text-[13px]`}
            value={element.osis}
            onChange={(e) => onChange({ ...element, osis: e.target.value })}
          />
        </Field>
        <button
          type="button"
          onClick={fetchText}
          disabled={looking || !element.citation.trim()}
          className="rounded-md border border-hairline bg-card px-3 py-1.5 text-[12.5px] text-ink-2 hover:bg-fill disabled:opacity-40"
        >
          {looking ? 'Fetching…' : 'Fill ESV text'}
        </button>
      </div>
      {note && <p className="m-0 text-[12px] text-red-800">{note}</p>}
      <Field label="Text" hint="Verse numbers inline (“3 Let the peoples…”); line breaks are kept">
        <textarea
          className={textareaClass}
          value={element.text}
          onChange={(e) => onChange({ ...element, text: e.target.value })}
        />
      </Field>
    </>
  );
}

function ElementFields(
  { element, onChange }: { element: WorshipElement; onChange: (e: WorshipElement) => void },
) {
  switch (element.type) {
    case 'scripture':
      return <ScriptureFields element={element} onChange={onChange} />;
    case 'prayer':
      return (
        <>
          <Field label="Prayer">
            <textarea className={textareaClass} value={element.text} onChange={(e) => onChange({ ...element, text: e.target.value })} />
          </Field>
          <label className="flex items-center gap-2 text-[13px] text-ink-2">
            <input
              type="checkbox"
              checked={Boolean(element.amen)}
              onChange={(e) => onChange({ ...element, amen: e.target.checked || undefined })}
            />
            Close with a spoken “Amen” cue
          </label>
        </>
      );
    case 'instruction':
      return (
        <Field label="Instruction">
          <textarea className={textareaClass} value={element.text} onChange={(e) => onChange({ ...element, text: e.target.value })} />
        </Field>
      );
    case 'song':
      return (
        <>
          <Field label="Title">
            <input className={inputClass} value={element.title} onChange={(e) => onChange({ ...element, title: e.target.value })} />
          </Field>
          <Field label="Lyrics">
            <textarea className={`${textareaClass} min-h-[9rem]`} value={element.lyrics} onChange={(e) => onChange({ ...element, lyrics: e.target.value })} />
          </Field>
        </>
      );
    case 'creed':
      return (
        <>
          <Field label="Title">
            <input className={inputClass} value={element.title} onChange={(e) => onChange({ ...element, title: e.target.value })} />
          </Field>
          <Field label="Text">
            <textarea className={`${textareaClass} min-h-[9rem]`} value={element.text} onChange={(e) => onChange({ ...element, text: e.target.value })} />
          </Field>
        </>
      );
    case 'catechism':
      return (
        <p className="m-0 text-[13px] italic text-ink-3">
          The household&rsquo;s current catechism question is shown here — it depends on their track, not this devotion.
        </p>
      );
    case 'prompts':
      return (
        <div className="flex flex-col gap-2">
          {element.items.map((item, i) => (
            <div key={i} className="grid gap-2 sm:grid-cols-[10rem_1fr_auto] sm:items-start">
              <input
                className={inputClass}
                placeholder="Label"
                value={item.label}
                onChange={(e) => onChange({ ...element, items: element.items.map((it, j) => (j === i ? { ...it, label: e.target.value } : it)) })}
              />
              <textarea
                className={`${inputClass} min-h-[3rem]`}
                placeholder="Prompt"
                value={item.text}
                onChange={(e) => onChange({ ...element, items: element.items.map((it, j) => (j === i ? { ...it, text: e.target.value } : it)) })}
              />
              <SmallButton
                onClick={() => onChange({ ...element, items: element.items.filter((_, j) => j !== i) })}
                disabled={element.items.length === 1}
              >
                Remove
              </SmallButton>
            </div>
          ))}
          <div>
            <SmallButton onClick={() => onChange({ ...element, items: [...element.items, { label: '', text: '' }] })}>
              + Prompt
            </SmallButton>
          </div>
        </div>
      );
    default:
      return null;
  }
}

function ElementCard(
  { element, index, count, onChange, onMove, onRemove }: {
    element: WorshipElement;
    index: number;
    count: number;
    onChange: (e: WorshipElement) => void;
    onMove: (delta: -1 | 1) => void;
    onRemove: () => void;
  },
) {
  const [showExtras, setShowExtras] = useState(Boolean(element.lede || element.source));
  return (
    <div className="flex flex-col gap-3 rounded-md border border-hairline-2 bg-card p-3">
      <div className="flex items-center justify-between gap-2">
        <span className="label-caps text-[9.5px] text-ink-2">{ELEMENT_LABELS[element.type]}</span>
        <div className="flex gap-1.5">
          <SmallButton onClick={() => setShowExtras((v) => !v)}>{showExtras ? 'Hide lede & link' : 'Lede & link'}</SmallButton>
          <SmallButton onClick={() => onMove(-1)} disabled={index === 0} title="Move up">↑</SmallButton>
          <SmallButton onClick={() => onMove(1)} disabled={index === count - 1} title="Move down">↓</SmallButton>
          <SmallButton onClick={onRemove} disabled={count === 1} title={count === 1 ? 'A step needs at least one element' : 'Remove'}>
            Remove
          </SmallButton>
        </div>
      </div>
      {showExtras && (
        <div className="grid gap-3 rounded border border-dashed border-muted p-2.5">
          <Field label="Lede" hint="Optional line introducing the element">
            <textarea
              className={`${inputClass} min-h-[3rem]`}
              value={element.lede ?? ''}
              onChange={(e) => onChange({ ...element, lede: e.target.value || undefined })}
            />
          </Field>
          <div className="grid gap-3 sm:grid-cols-[1fr_1fr_auto] sm:items-end">
            <Field label="Source label" hint="e.g. Listen on YouTube">
              <input
                className={inputClass}
                value={element.source?.label ?? ''}
                onChange={(e) => onChange({ ...element, source: { href: element.source?.href ?? '', external: element.source?.external, label: e.target.value } })}
              />
            </Field>
            <Field label="Source link">
              <input
                className={inputClass}
                value={element.source?.href ?? ''}
                onChange={(e) => onChange({ ...element, source: { label: element.source?.label ?? '', external: element.source?.external, href: e.target.value } })}
              />
            </Field>
            <div className="flex gap-2 pb-1">
              <label className="flex items-center gap-1.5 text-[12.5px] text-ink-2">
                <input
                  type="checkbox"
                  checked={Boolean(element.source?.external)}
                  onChange={(e) => onChange({ ...element, source: { label: element.source?.label ?? '', href: element.source?.href ?? '', external: e.target.checked || undefined } })}
                />
                Leaves the app
              </label>
              {element.source && (
                <SmallButton onClick={() => onChange({ ...element, source: undefined })}>Clear</SmallButton>
              )}
            </div>
          </div>
        </div>
      )}
      <ElementFields element={element} onChange={onChange} />
    </div>
  );
}

// ---------------------------------------------------------------------------

/** Drops empty optional fields so the saved JSON matches hand-authored
 * files (no `"lede": ""`, no half-filled `source`). */
const cleanDevotion = (devotion: Devotion): Devotion => ({
  ...devotion,
  slug: devotion.slug.trim(),
  steps: devotion.steps.map((step) => ({
    ...step,
    elements: step.elements.map((element) => {
      const copy = { ...element } as WorshipElement & Record<string, unknown>;
      if (!copy.lede?.trim()) delete copy.lede;
      if (copy.source && !copy.source.label.trim() && !copy.source.href.trim()) delete copy.source;
      if (copy.type === 'prayer' && !copy.amen) delete copy.amen;
      return copy;
    }),
  })),
});

export function DevotionEditor(
  { initial, series, isNew, pending: initialPending, published = true, mode }: {
    initial: Devotion;
    series: DevotionSeries[];
    isNew: boolean;
    pending: { url: string; number: number } | null;
    /** Whether a live version exists (on the base branch, or on disk). */
    published?: boolean;
    mode: 'local' | 'github';
  },
) {
  const [devotion, setDevotion] = useState(initial);
  const [link, setLink] = useState<SeriesLink | null>(() => findSeriesLink(series, initial.slug || '\0'));
  const [saved, setSaved] = useState<SaveResponse | null>(null);
  const [savedAs, setSavedAs] = useState<string | null>(isNew ? null : initial.slug);
  const [saving, startSave] = useTransition();
  const [dirty, setDirty] = useState(false);

  const update = (next: Devotion) => {
    setDevotion(next);
    setDirty(true);
  };
  const updateElements = (stepIndex: number, fn: (elements: WorshipElement[]) => WorshipElement[]) => update({
    ...devotion,
    steps: devotion.steps.map((step, i) => (i === stepIndex ? { ...step, elements: fn(step.elements) } : step)),
  });

  const cleaned = useMemo(() => cleanDevotion(devotion), [devotion]);
  // existing slugs are only known server-side; the save re-checks them
  const errors = useMemo(() => validateDevotion(cleaned), [cleaned]);
  const creating = savedAs === null;

  const save = () => startSave(async () => {
    const response = await saveDevotion({ devotion: cleaned, link, isNew: creating });
    setSaved(response);
    if (response.ok) {
      setDirty(false);
      setSavedAs(cleaned.slug);
      if (creating) window.history.replaceState(null, '', `/admin/devotions/${cleaned.slug}`);
    }
  });

  const pendingPr = saved?.ok && saved.result.mode === 'github' ? saved.result.pullRequest : initialPending;

  return (
    <div className="flex flex-col gap-6">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <h1 className="m-0 heading-page">{devotion.title || (creating ? 'New devotion' : 'Untitled')}</h1>
          <DraftStatus
            kind="devotion"
            slug={devotion.slug}
            creating={creating}
            published={published || (mode === 'local' && !creating)}
            pending={pendingPr}
          />
        </div>
      </div>

      <section className="flex flex-col gap-3 rounded-md border border-hairline bg-white p-4">
        <h2 className="m-0 heading-section">About this devotion</h2>
        <div className="grid gap-3 sm:grid-cols-2">
          <Field label="Title" hint="Usually the question or passage, e.g. What is the chief end of man?">
            <input className={inputClass} value={devotion.title} onChange={(e) => update({ ...devotion, title: e.target.value })} />
          </Field>
          <Field label="Slug" hint={creating ? 'The URL: /devotions/<slug>. Fixed once saved.' : 'Fixed — it is the devotion’s URL.'}>
            <input
              className={`${inputClass} font-mono text-[13px] disabled:bg-fill`}
              value={devotion.slug}
              disabled={!creating}
              onChange={(e) => update({ ...devotion, slug: e.target.value.toLowerCase().replace(/[^a-z0-9-]/g, '-') })}
            />
          </Field>
        </div>
        <Field label="Summary" hint="One line for the hub card">
          <input className={inputClass} value={devotion.summary} onChange={(e) => update({ ...devotion, summary: e.target.value })} />
        </Field>
        <Field label="Description" hint="The landing page’s paragraph: what’s inside and why it’s grounded this way">
          <textarea className={textareaClass} value={devotion.description} onChange={(e) => update({ ...devotion, description: e.target.value })} />
        </Field>
        <GroundingFields grounding={devotion.grounding} onChange={(grounding) => update({ ...devotion, grounding })} />
        <SeriesFields
          series={series}
          slug={devotion.slug}
          link={link}
          onChange={(next) => { setLink(next); setDirty(true); }}
        />
      </section>

      {devotion.steps.map((step, stepIndex) => (
        <section key={step.role} className="flex flex-col gap-3 rounded-md border border-hairline bg-white p-4">
          <h2 className="m-0 heading-section">
            <span className="mr-2 text-ink-3">{stepIndex + 1}.</span>{step.role}
          </h2>
          {step.elements.map((element, i) => (
            <ElementCard
              // elements carry no ids; position + type is stable enough here
              key={`${i}-${element.type}`}
              element={element}
              index={i}
              count={step.elements.length}
              onChange={(next) => updateElements(stepIndex, (els) => els.map((el, j) => (j === i ? next : el)))}
              onMove={(delta) => updateElements(stepIndex, (els) => {
                const copy = [...els];
                [copy[i], copy[i + delta]] = [copy[i + delta], copy[i]];
                return copy;
              })}
              onRemove={() => updateElements(stepIndex, (els) => els.filter((_, j) => j !== i))}
            />
          ))}
          <div className="flex flex-wrap items-center gap-1.5">
            <span className="text-[12px] text-ink-3">Add:</span>
            {ELEMENT_TYPES.map((type) => (
              <SmallButton key={type} onClick={() => updateElements(stepIndex, (els) => [...els, blankElement(type)])}>
                {ELEMENT_LABELS[type]}
              </SmallButton>
            ))}
          </div>
        </section>
      ))}

      <div className="sticky bottom-0 -mx-4 flex flex-col gap-2 border-t border-hairline bg-card/95 px-4 py-3 backdrop-blur sm:-mx-8 sm:px-8">
        {saved && !saved.ok && (
          <ul className="m-0 list-disc pl-5 text-[13px] text-red-800" role="alert">
            {saved.errors.map((e) => <li key={e}>{e}</li>)}
          </ul>
        )}
        {saved?.ok && !dirty && (
          <p className="m-0 text-[13px] text-ink-2" role="status">
            {saved.result.mode === 'local'
              ? `Saved ${saved.result.paths.join(', ')}. Commit it when you're ready.`
              : (
                <>
                  {saved.result.opened ? 'Opened' : 'Added a commit to'}{' '}
                  <a href={saved.result.pullRequest.url} target="_blank" rel="noreferrer" className="text-ochre">
                    pull request #{saved.result.pullRequest.number} ↗
                  </a>
                  . It goes live on the web once merged and deployed.
                </>
              )}
          </p>
        )}
        <div className="flex flex-wrap items-center justify-between gap-3">
          {errors.length ? (
            <details className="max-w-[44rem] text-[12.5px] text-ink-3">
              <summary className="cursor-pointer">
                {errors.length} thing{errors.length === 1 ? '' : 's'} to fix before saving: {errors[0]}
              </summary>
              <ul className="m-0 mt-1 max-h-40 list-disc overflow-y-auto pl-5">
                {errors.map((e) => <li key={e}>{e}</li>)}
              </ul>
            </details>
          ) : (
            <span className="text-[12.5px] text-ink-3">{dirty ? 'Unsaved changes' : 'No changes'}</span>
          )}
          <button
            type="button"
            onClick={save}
            disabled={saving || errors.length > 0 || !dirty}
            className="rounded-md bg-ink px-5 py-2 label-caps text-[11px] text-card disabled:opacity-40"
          >
            {saving ? 'Saving…' : mode === 'github' ? (pendingPr ? 'Save to pull request' : 'Save & open pull request') : 'Save'}
          </button>
        </div>
      </div>
    </div>
  );
}
