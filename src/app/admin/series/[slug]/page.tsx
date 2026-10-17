import { notFound } from 'next/navigation';

import { getDevotionStore } from '@/lib/admin/store';
import { AdminHeader } from '../../AdminHeader';
import { SeriesEditor } from '../SeriesEditor';

export const dynamic = 'force-dynamic';

export async function generateMetadata({ params }: { params: Promise<{ slug: string }> }) {
  const { slug } = await params;
  return { title: `Edit ${slug} series` };
}

export default async function EditSeriesPage({ params }: { params: Promise<{ slug: string }> }) {
  const { slug } = await params;
  const setup = getDevotionStore();
  if (!setup.ok) {
    return (
      <>
        <AdminHeader section="series" crumbs={[{ label: slug }]} />
        <p className="text-[14px] text-ink-2">{setup.reason}</p>
      </>
    );
  }
  const loaded = await setup.store.loadSeries(slug);
  if (!loaded) notFound();

  return (
    <>
      <AdminHeader section="series" crumbs={[{ label: loaded.series.title || slug }]} />
      <SeriesEditor
        initial={loaded.series}
        isNew={false}
        lockedParts={loaded.lockedParts}
        otherSeries={loaded.otherSeries}
        pending={loaded.pending}
        mode={setup.store.mode}
      />
    </>
  );
}
