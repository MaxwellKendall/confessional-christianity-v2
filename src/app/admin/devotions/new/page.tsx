// A new devotion starts blank (the eight steps with their usual first
// elements) or as a copy of an existing devotion's liturgy — most share
// their prayers and songs, so copying is usually the faster start.
import { blankDevotion, devotionFrom } from '@/lib/admin/devotionDraft';
import { getDevotionStore } from '@/lib/admin/store';
import { AdminHeader } from '../../AdminHeader';
import { DevotionEditor } from '../DevotionEditor';

export const dynamic = 'force-dynamic';
export const metadata = { title: 'New devotion' };

export default async function NewDevotionPage(
  { searchParams }: { searchParams: Promise<{ from?: string }> },
) {
  const { from } = await searchParams;
  const setup = getDevotionStore();
  if (!setup.ok) {
    return (
      <>
        <AdminHeader crumbs={[{ label: 'New devotion' }]} />
        <p className="text-[14px] text-ink-2">{setup.reason}</p>
      </>
    );
  }
  const { store } = setup;
  const [rows, series, template] = await Promise.all([
    store.list(),
    store.series(),
    from ? store.load(from) : Promise.resolve(null),
  ]);
  const initial = template ? devotionFrom(template.devotion) : blankDevotion();

  return (
    <>
      <AdminHeader crumbs={[{ label: 'New devotion' }]} />
      <form method="get" className="mb-6 flex flex-wrap items-end gap-2 rounded-md border border-dashed border-muted p-3">
        <label className="flex flex-col gap-1">
          <span className="label-caps text-[9.5px] text-ink-3">Start from</span>
          <select
            name="from"
            defaultValue={template ? template.devotion.slug : ''}
            className="rounded-md border border-hairline bg-white px-2.5 py-1.5 text-[14px]"
          >
            <option value="">A blank devotion</option>
            {rows.map(({ devotion }) => (
              <option key={devotion.slug} value={devotion.slug}>
                A copy of {devotion.title} ({devotion.slug})
              </option>
            ))}
          </select>
        </label>
        <button type="submit" className="rounded-md border border-hairline bg-card px-3 py-1.5 text-[13px] text-ink-2">
          Start over from this
        </button>
        <span className="text-[12px] text-ink-3">Replaces anything typed below.</span>
      </form>
      <DevotionEditor
        key={from ?? 'blank'}
        initial={initial}
        series={series}
        isNew
        pending={null}
        mode={store.mode}
      />
    </>
  );
}
