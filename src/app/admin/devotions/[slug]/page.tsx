import { notFound } from 'next/navigation';

import { getDevotionStore } from '@/lib/admin/store';
import { AdminHeader } from '../../AdminHeader';
import { DevotionEditor } from '../DevotionEditor';

export const dynamic = 'force-dynamic';

export async function generateMetadata({ params }: { params: Promise<{ slug: string }> }) {
  const { slug } = await params;
  return { title: `Edit ${slug}` };
}

export default async function EditDevotionPage({ params }: { params: Promise<{ slug: string }> }) {
  const { slug } = await params;
  const setup = getDevotionStore();
  if (!setup.ok) {
    return (
      <>
        <AdminHeader crumbs={[{ label: slug }]} />
        <p className="text-[14px] text-ink-2">{setup.reason}</p>
      </>
    );
  }
  const loaded = await setup.store.load(slug);
  if (!loaded) notFound();

  return (
    <>
      <AdminHeader crumbs={[{ label: loaded.devotion.title || slug }]} />
      <DevotionEditor
        initial={loaded.devotion}
        series={loaded.series}
        isNew={false}
        pending={loaded.pending}
        published={loaded.published}
        mode={setup.store.mode}
      />
    </>
  );
}
