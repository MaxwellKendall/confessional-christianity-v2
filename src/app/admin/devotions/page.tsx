// Every devotion, published and in review, with where it sits in a series.
import Link from 'next/link';

import { getDevotionStore } from '@/lib/admin/store';
import { findSeriesLink } from '@/lib/devotionValidation';
import { groundingLabel } from '@/lib/devotions';
import { AdminHeader } from '../AdminHeader';
import { FeaturedPicker } from '../FeaturedPicker';

export const dynamic = 'force-dynamic';
export const metadata = { title: 'Devotions' };

export default async function AdminDevotionsPage() {
  const setup = getDevotionStore();
  if (!setup.ok) {
    return (
      <>
        <AdminHeader />
        <p className="text-[14px] text-ink-2">{setup.reason}</p>
      </>
    );
  }
  const [rows, series, featured] = await Promise.all([
    setup.store.list(), setup.store.series(), setup.store.featured(),
  ]);
  const inReview = rows.filter((r) => r.pending).length;

  return (
    <>
      <AdminHeader />
      <div className="mb-4 flex flex-wrap items-end justify-between gap-3">
        <div>
          <h1 className="m-0 heading-page">Devotions</h1>
          <p className="m-0 mt-1 text-[13px] text-ink-3">
            {rows.length} authored{inReview ? ` · ${inReview} in review` : ''}
          </p>
        </div>
        <Link
          href="/admin/devotions/new"
          className="rounded-md bg-ink px-4 py-2 label-caps text-[11px] text-card no-underline"
        >
          New devotion
        </Link>
      </div>

      <FeaturedPicker
        current={featured.slug}
        pending={featured.pending}
        options={rows.filter((r) => r.published).map(({ devotion }) => ({ slug: devotion.slug, title: devotion.title }))}
      />

      <div className="overflow-x-auto rounded-md border border-hairline bg-white">
        <table className="w-full border-collapse text-left text-[13.5px]">
          <thead>
            <tr className="label-caps border-b border-hairline text-[9.5px] text-ink-3">
              <th className="px-3 py-2 font-normal">Devotion</th>
              <th className="px-3 py-2 font-normal">Grounded in</th>
              <th className="px-3 py-2 font-normal">Series</th>
              <th className="px-3 py-2 font-normal">Status</th>
            </tr>
          </thead>
          <tbody>
            {rows.map(({ devotion, published, pending }) => {
              const link = findSeriesLink(series, devotion.slug);
              const linkedSeries = link && series.find((s) => s.slug === link.seriesSlug);
              return (
                <tr key={devotion.slug} className="border-b border-hairline-2 last:border-0 align-top">
                  <td className="px-3 py-2.5">
                    <Link href={`/admin/devotions/${devotion.slug}`} className="text-ink no-underline">
                      {devotion.title || <em className="text-ink-3">Untitled</em>}
                    </Link>
                    <div className="flex gap-2 font-mono text-[11px] text-ink-3">
                      {devotion.slug}
                      {devotion.slug === featured.slug && <span className="font-body text-ochre">· featured</span>}
                      {published && (
                        <Link href={`/devotions/${devotion.slug}`} target="_blank" className="font-body text-ink-3">
                          view ↗
                        </Link>
                      )}
                    </div>
                  </td>
                  <td className="px-3 py-2.5 whitespace-nowrap text-ink-2">{groundingLabel(devotion.grounding)}</td>
                  <td className="px-3 py-2.5 text-ink-2">
                    {linkedSeries ? (
                      <Link href={`/admin/series/${linkedSeries.slug}`} className="text-ink-2 no-underline">
                        {linkedSeries.title} · Part {link.day}
                      </Link>
                    ) : '—'}
                  </td>
                  <td className="px-3 py-2.5 whitespace-nowrap">
                    {pending ? (
                      <a href={pending.url} target="_blank" rel="noreferrer" className="text-ochre">
                        {published ? 'Edits in review' : 'New, in review'} · #{pending.number} ↗
                      </a>
                    ) : (
                      <span className="text-ink-3">{setup.store.mode === 'local' ? 'On disk' : 'Published'}</span>
                    )}
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>
    </>
  );
}
