import Link from 'next/link';

// Placeholder homepage after TKL-856 cut devotions, reading plans, Family
// Worship and the web catechism session: the site now serves reading (the
// Library) and the essays (Reflections); catechizing a child happens in the
// iOS app.
const CATECHISMS = [
  { slug: 'westminster-shorter-catechism', title: 'Westminster Shorter Catechism', count: '107 Q&A' },
  { slug: 'westminster-larger-catechism', title: 'Westminster Larger Catechism', count: '196 Q&A' },
  { slug: 'heidelberg-catechism', title: 'Heidelberg Catechism', count: '129 Q&A' },
];

export default function Home() {
  return (
    <div className="mx-auto w-full max-w-5xl px-5 pt-7 pb-10 sm:px-10 sm:pt-12 sm:pb-16">
      <div className="label-caps mb-2.5 text-[9.5px] tracking-[0.14em] text-ink-3 sm:mb-3.5 sm:text-[11px]">
        The Catechisms
      </div>
      <div className="grid grid-cols-1 gap-3 sm:grid-cols-3 sm:gap-5">
        {CATECHISMS.map((c) => (
          <Link
            key={c.slug}
            href={`/library/${c.slug}`}
            className="block rounded-sm bg-fill px-5 py-5 text-ink no-underline sm:px-7 sm:py-7"
          >
            <div className="font-display text-[14px] font-semibold leading-snug sm:text-[15.5px]">
              {c.title}
            </div>
            <div className="label-caps mt-1.5 text-[9px] tracking-[0.1em] text-ink-3 sm:mt-2.5 sm:text-[10.5px]">
              {c.count}
            </div>
          </Link>
        ))}
      </div>

      <div className="mt-9 border-t border-hairline pt-5 text-center sm:mt-14 sm:pt-7">
        <span className="text-[13px] italic text-ink-2 sm:text-[15px]">
          Read every confession and catechism in the{' '}
          <Link href="/library" className="dotted-link text-ink">Library</Link>, or the essays in{' '}
          <Link href="/reflections" className="dotted-link text-ink">Reflections</Link>.
        </span>
      </div>
    </div>
  );
}
