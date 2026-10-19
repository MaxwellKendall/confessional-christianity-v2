// Every devotion series, published and in review.
import Link from 'next/link';

import { getDevotionStore } from '@/lib/admin/store';
import { seriesSourceLabel } from '@/lib/devotionSeries';
import { AdminHeader } from '../AdminHeader';

export const dynamic = 'force-dynamic';
export const metadata = { title: 'Series' };

export default async function AdminSeriesPage() {
  const setup = getDevotionStore();
  if (!setup.ok) {
    return (
      <>
        <AdminHeader section="series" />
        <p className="text-[14px] text-ink-2">{setup.reason}</p>
      </>
    );
  }
  const rows = await setup.store.listSeries();

  return (
    <>
      <AdminHeader section="series" />
      <div className="mb-4 flex flex-wrap items-end justify-between gap-3">
        <div>
          <h1 className="m-0 heading-page">Series</h1>
          <p className="m-0 mt-1 max-w-[36rem] text-[13px] text-ink-3">
            Ordered runs of devotions over a season or a catechism. Add a devotion to a part from the devotion&rsquo;s own editor.
          </p>
        </div>
        <Link
          href="/admin/series/new"
          className="rounded-md bg-ink px-4 py-2 label-caps text-[11px] text-card no-underline"
        >
          New series
        </Link>
      </div>

      <div className="overflow-x-auto rounded-md border border-hairline bg-white">
        <table className="w-full border-collapse text-left text-[13.5px]">
          <thead>
            <tr className="label-caps border-b border-hairline text-[9.5px] text-ink-3">
              <th className="px-3 py-2 font-normal">Series</th>
              <th className="px-3 py-2 font-normal">Over</th>
              <th className="px-3 py-2 font-normal">Parts written</th>
              <th className="px-3 py-2 font-normal">Status</th>
            </tr>
          </thead>
          <tbody>
            {rows.map(({ series, published, pending }) => (
              <tr key={series.slug} className="border-b border-hairline-2 last:border-0 align-top">
                <td className="px-3 py-2.5">
                  <Link href={`/admin/series/${series.slug}`} className="text-ink no-underline">{series.title}</Link>
                  <div className="flex gap-2 font-mono text-[11px] text-ink-3">
                    {series.slug}
                    {published && (
                      <Link href={`/devotions/${series.slug}`} target="_blank" className="font-body text-ink-3">view ↗</Link>
                    )}
                  </div>
                </td>
                <td className="px-3 py-2.5 whitespace-nowrap text-ink-2">{seriesSourceLabel(series)}</td>
                <td className="px-3 py-2.5 whitespace-nowrap text-ink-2">
                  {series.parts.filter((p) => p.devotionSlug).length} of {series.parts.length}
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
            ))}
          </tbody>
        </table>
      </div>
    </>
  );
}
