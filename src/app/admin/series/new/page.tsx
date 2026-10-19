import { blankSeries } from '@/lib/admin/devotionDraft';
import { getDevotionStore } from '@/lib/admin/store';
import { AdminHeader } from '../../AdminHeader';
import { SeriesEditor } from '../SeriesEditor';

export const dynamic = 'force-dynamic';
export const metadata = { title: 'New series' };

export default async function NewSeriesPage() {
  const setup = getDevotionStore();
  if (!setup.ok) {
    return (
      <>
        <AdminHeader section="series" crumbs={[{ label: 'New series' }]} />
        <p className="text-[14px] text-ink-2">{setup.reason}</p>
      </>
    );
  }
  return (
    <>
      <AdminHeader section="series" crumbs={[{ label: 'New series' }]} />
      <SeriesEditor
        initial={blankSeries()}
        isNew
        lockedParts={0}
        otherSeries={await setup.store.series()}
        pending={null}
        published={false}
        mode={setup.store.mode}
      />
    </>
  );
}
