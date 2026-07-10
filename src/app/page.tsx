import Link from 'next/link';

// Placeholder homepage until the programs-led homepage lands (Phase 6):
// programs first, then the library line, per PRD §8.
export default function Home() {
  return (
    <div className="px-6 pt-10 pb-12 text-center">
      <div className="label-caps mb-3 text-ink-3">Family Catechesis</div>
      <h1 className="font-display text-xl font-semibold">Catechizing Your Child</h1>
      <p className="mt-3 font-body italic text-[13.5px] leading-relaxed text-ink-2">
        Programs are coming together. Meanwhile, the confessions and catechisms
        are all here to read.
      </p>
      <div className="mx-5 mt-8 border-t border-hairline pt-5 text-[13px] italic text-ink-2">
        Explore the confessions and catechisms directly in the{' '}
        <Link href="/library" className="dotted-link text-ink">Library</Link>.
      </div>
    </div>
  );
}
