'use client';

// The hub's "Featured This Week" pick, rotated from the devotions list.
import { useState, useTransition } from 'react';

import { setFeaturedDevotion, type SaveResponse } from './actions';

export function FeaturedPicker(
  { current, options, pending }: {
    current: string;
    options: { slug: string; title: string }[];
    pending: { url: string; number: number } | null;
  },
) {
  const [choice, setChoice] = useState(current);
  const [saved, setSaved] = useState<SaveResponse | null>(null);
  const [saving, startSave] = useTransition();
  const [live, setLive] = useState(current);

  const save = () => startSave(async () => {
    const response = await setFeaturedDevotion(choice);
    setSaved(response);
    if (response.ok) setLive(choice);
  });

  const pr = saved?.ok && saved.result.mode === 'github' ? saved.result.pullRequest : pending;

  return (
    <div className="mb-4 flex flex-wrap items-end gap-2 rounded-md border border-hairline bg-white p-3">
      <label className="flex min-w-[16rem] flex-1 flex-col gap-1">
        <span className="label-caps text-[9.5px] text-ochre">Featured this week</span>
        <select
          value={choice}
          onChange={(e) => setChoice(e.target.value)}
          className="rounded-md border border-hairline bg-white px-2.5 py-1.5 font-body text-[14px]"
        >
          {options.map((o) => <option key={o.slug} value={o.slug}>{o.title} ({o.slug})</option>)}
        </select>
      </label>
      <button
        type="button"
        onClick={save}
        disabled={saving || choice === live}
        className="rounded-md border border-hairline bg-card px-3 py-1.5 text-[13px] text-ink-2 hover:bg-fill disabled:opacity-40"
      >
        {saving ? 'Saving…' : 'Feature it'}
      </button>
      <div className="basis-full text-[12px] text-ink-3" role="status">
        {saved && !saved.ok && <span className="text-red-800">{saved.errors.join(' ')}</span>}
        {saved?.ok && saved.result.mode === 'local' && `Saved ${saved.result.paths.join(', ')}.`}
        {pr && (
          <>
            Change in review in{' '}
            <a href={pr.url} target="_blank" rel="noreferrer" className="text-ochre">pull request #{pr.number} ↗</a>
            {' '}— the hub switches once it merges.
          </>
        )}
        {!saved && !pr && 'Only published devotions can be featured.'}
      </div>
    </div>
  );
}
