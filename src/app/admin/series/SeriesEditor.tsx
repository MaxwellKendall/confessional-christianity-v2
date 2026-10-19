'use client';

// The series editor: name, tagline, description, what the run is ordered
// over (a season or a catechism), and its parts — each a title and citation,
// named up front even before a devotion is written for it. Devotions are
// attached from the devotion editor, so links show here read-only. Parts
// households already have stay in place (progress is stored by day number);
// new parts can be added after them, moved, and removed.
import Link from 'next/link';
import { useMemo, useState, useTransition } from 'react';

import { CREEDAL_DOCUMENTS } from '@/lib/catechisms';
import type { DevotionSeries, SeriesPart, SeriesSource } from '@/lib/devotionSeries';
import { SEASONS } from '@/lib/devotions';
import { validateSeries } from '@/lib/devotionValidation';
import { prefillCatechismParts, saveSeries, type SaveResponse } from '../actions';
import { DraftStatus } from '../DraftStatus';

const inputClass = 'w-full rounded-md border border-hairline bg-white px-2.5 py-1.5 font-body text-[14px] text-ink';

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

const renumber = (parts: SeriesPart[]): SeriesPart[] => parts.map((p, i) => ({ ...p, day: i + 1 }));

export function SeriesEditor(
  { initial, isNew, lockedParts, otherSeries, pending: initialPending, published = true, mode }: {
    initial: DevotionSeries;
    isNew: boolean;
    lockedParts: number;
    otherSeries: DevotionSeries[];
    pending: { url: string; number: number } | null;
    /** Whether a live version exists (on the base branch, or on disk). */
    published?: boolean;
    mode: 'local' | 'github';
  },
) {
  const [series, setSeries] = useState(initial);
  const [dirty, setDirty] = useState(false);
  const [saved, setSaved] = useState<SaveResponse | null>(null);
  const [savedAs, setSavedAs] = useState<string | null>(isNew ? null : initial.slug);
  const [saving, startSave] = useTransition();
  const [prefilling, startPrefill] = useTransition();
  const creating = savedAs === null;

  const update = (next: DevotionSeries) => {
    setSeries(next);
    setDirty(true);
  };
  const setParts = (parts: SeriesPart[]) => update({ ...series, parts: renumber(parts) });

  const cleaned = useMemo(() => ({ ...series, slug: series.slug.trim() }), [series]);
  const errors = useMemo(() => validateSeries(cleaned, { otherSeries }), [cleaned, otherSeries]);
  const lastLinked = Math.max(0, ...series.parts.filter((p) => p.devotionSlug).map((p) => p.day));
  // a part can move or go only if it's past what households have and isn't
  // carrying a devotion (links are keyed by day)
  const fixed = (i: number) => i < lockedParts || Boolean(series.parts[i]?.devotionSlug);

  const switchSource = (kind: SeriesSource['kind']) => update({
    ...series,
    source: kind === 'season'
      ? { kind, season: SEASONS[0].slug }
      : { kind, documentId: 'WSC' },
  });

  const prefill = () => startPrefill(async () => {
    if (series.source.kind === 'catechism') {
      const parts = await prefillCatechismParts(series.source.documentId);
      // keep the fixed leading parts; fill in everything after them
      setParts([...series.parts.slice(0, lockedParts), ...parts.slice(lockedParts)]);
    } else {
      const { season } = series.source;
      const days = SEASONS.find((s) => s.slug === season)?.days ?? 0;
      const extra = Array.from({ length: Math.max(0, days - series.parts.length) }, () => ({
        day: 0, title: '', citation: '',
      }));
      setParts([...series.parts, ...extra]);
    }
  });

  const save = () => startSave(async () => {
    const response = await saveSeries({ series: cleaned, isNew: creating });
    setSaved(response);
    if (response.ok) {
      setDirty(false);
      setSavedAs(cleaned.slug);
      if (creating) window.history.replaceState(null, '', `/admin/series/${cleaned.slug}`);
    }
  });

  const pendingPr = saved?.ok && saved.result.mode === 'github' ? saved.result.pullRequest : initialPending;
  const seasonDays = series.source.kind === 'season'
    ? SEASONS.find((s) => s.slug === (series.source as { season: string }).season)?.days
    : undefined;

  return (
    <div className="flex flex-col gap-6">
      <div>
        <h1 className="m-0 heading-page">{series.title || (creating ? 'New series' : 'Untitled')}</h1>
        <DraftStatus
          kind="series"
          slug={series.slug}
          creating={creating}
          published={published || (mode === 'local' && !creating)}
          pending={pendingPr}
        />
      </div>

      <section className="flex flex-col gap-3 rounded-md border border-hairline bg-white p-4">
        <h2 className="m-0 heading-section">About this series</h2>
        <div className="grid gap-3 sm:grid-cols-2">
          <Field label="Title" hint="The series’ own name, e.g. Prepare the Way">
            <input className={inputClass} value={series.title} onChange={(e) => update({ ...series, title: e.target.value })} />
          </Field>
          <Field label="Slug" hint={creating ? 'The URL: /devotions/<slug>. Fixed once saved.' : 'Fixed — it is the series’ URL and its progress key.'}>
            <input
              className={`${inputClass} font-mono text-[13px] disabled:bg-fill`}
              value={series.slug}
              disabled={!creating}
              onChange={(e) => update({ ...series, slug: e.target.value.toLowerCase().replace(/[^a-z0-9-]/g, '-') })}
            />
          </Field>
        </div>
        <Field label="Tagline" hint="The landing page subtitle, e.g. Waiting, Longing, Fulfillment">
          <input className={inputClass} value={series.tagline} onChange={(e) => update({ ...series, tagline: e.target.value })} />
        </Field>
        <Field label="Description" hint="The arc, and that each part builds on the last">
          <textarea
            className={`${inputClass} min-h-[5.5rem] leading-relaxed`}
            value={series.description}
            onChange={(e) => update({ ...series, description: e.target.value })}
          />
        </Field>
        <div className="grid gap-3 sm:grid-cols-[16rem_1fr]">
          <Field label="Ordered over" hint={creating ? undefined : 'Fixed once saved'}>
            <select
              className={`${inputClass} disabled:bg-fill`}
              value={series.source.kind}
              disabled={!creating}
              onChange={(e) => switchSource(e.target.value as SeriesSource['kind'])}
            >
              <option value="season">A season</option>
              <option value="catechism">A confession or catechism</option>
            </select>
          </Field>
          {series.source.kind === 'season' ? (
            <Field label="Season" hint="The hub’s season card opens this series">
              <select
                className={`${inputClass} disabled:bg-fill`}
                value={series.source.season}
                disabled={!creating}
                onChange={(e) => update({ ...series, source: { kind: 'season', season: e.target.value } })}
              >
                {SEASONS.map((s) => <option key={s.slug} value={s.slug}>{s.name} ({s.days} days)</option>)}
              </select>
            </Field>
          ) : (
            <Field label="Document" hint="The hub’s Confession & Catechism row links to this series">
              <select
                className={`${inputClass} disabled:bg-fill`}
                value={series.source.documentId}
                disabled={!creating}
                onChange={(e) => update({ ...series, source: { kind: 'catechism', documentId: e.target.value } })}
              >
                {Object.values(CREEDAL_DOCUMENTS).map((d) => <option key={d.id} value={d.id}>{d.name}</option>)}
              </select>
            </Field>
          )}
        </div>
      </section>

      <section className="flex flex-col gap-3 rounded-md border border-hairline bg-white p-4">
        <div className="flex flex-wrap items-baseline justify-between gap-2">
          <h2 className="m-0 heading-section">Parts</h2>
          <span className="text-[12px] text-ink-3">
            {series.parts.length} part{series.parts.length === 1 ? '' : 's'}
            {seasonDays ? ` of up to ${seasonDays}` : ''}
            {lockedParts ? ` · the first ${lockedParts} are published and stay in place` : ''}
          </span>
        </div>
        <p className="m-0 text-[12.5px] text-ink-3">
          Name every part up front: the series page shows the whole arc, with unwritten parts marked &ldquo;in preparation.&rdquo;
        </p>
        <div className="flex flex-wrap gap-2">
          <SmallButton
            onClick={prefill}
            disabled={prefilling || (series.source.kind === 'season' && series.parts.length >= (seasonDays ?? 0))}
            title={series.source.kind === 'catechism'
              ? 'One part per question (or Lord’s Day), titled from the document'
              : 'Blank parts up to the season’s length'}
          >
            {prefilling ? 'Filling…' : series.source.kind === 'catechism'
              ? `Fill parts from the ${CREEDAL_DOCUMENTS[series.source.documentId]?.shortName ?? 'document'}`
              : 'Add a part for every day'}
          </SmallButton>
        </div>

        {series.parts.length > 0 && (
          <ol className="m-0 flex list-none flex-col gap-1.5 p-0">
            {series.parts.map((part, i) => (
              <li key={i} className="grid items-start gap-2 sm:grid-cols-[2.25rem_1fr_13rem_auto]">
                <span className="pt-1.5 text-right font-display text-[12px] text-ink-3">{part.day}.</span>
                <input
                  className={inputClass}
                  placeholder="Title"
                  aria-label={`Part ${part.day} title`}
                  value={part.title}
                  onChange={(e) => setParts(series.parts.map((p, j) => (j === i ? { ...p, title: e.target.value } : p)))}
                />
                <input
                  className={inputClass}
                  placeholder="Citation, e.g. Isaiah 7:10–14"
                  aria-label={`Part ${part.day} citation`}
                  value={part.citation}
                  onChange={(e) => setParts(series.parts.map((p, j) => (j === i ? { ...p, citation: e.target.value } : p)))}
                />
                <div className="flex items-center gap-1.5 pt-1">
                  {part.devotionSlug ? (
                    <Link href={`/admin/devotions/${part.devotionSlug}`} className="text-[12px] text-ochre no-underline" title="Linked devotion">
                      {part.devotionSlug}
                    </Link>
                  ) : fixed(i) ? (
                    <span className="text-[12px] text-ink-3">Published</span>
                  ) : (
                    <>
                      <SmallButton onClick={() => { const c = [...series.parts]; [c[i - 1], c[i]] = [c[i], c[i - 1]]; setParts(c); }} disabled={i === 0 || fixed(i - 1)} title="Move up">↑</SmallButton>
                      <SmallButton onClick={() => { const c = [...series.parts]; [c[i + 1], c[i]] = [c[i], c[i + 1]]; setParts(c); }} disabled={i === series.parts.length - 1 || fixed(i + 1)} title="Move down">↓</SmallButton>
                      <SmallButton
                        onClick={() => setParts(series.parts.filter((_, j) => j !== i))}
                        disabled={i < lastLinked}
                        title={i < lastLinked ? 'Removing it would shift a linked part’s day' : 'Remove'}
                      >
                        Remove
                      </SmallButton>
                    </>
                  )}
                </div>
              </li>
            ))}
          </ol>
        )}
        <div>
          <SmallButton
            onClick={() => setParts([...series.parts, { day: 0, title: '', citation: '' }])}
            disabled={seasonDays !== undefined && series.parts.length >= seasonDays}
          >
            + Part
          </SmallButton>
        </div>
      </section>

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
