// The devotions hub (mockup 15a): a featured slot up top so scale never
// feels like a database dump — the editorial pick, or a Continue card once
// a series is in progress (turn 16) — then one distinctly-treated row per
// grounding axis — Confession & Catechism, Scripture, Topic, Season —
// echoing 10a's "each kind its own treatment" pattern. Catechism leads
// (turn 17): with the WSC run 66 questions deep, it's the most substantial
// axis in the library, so it gets the first row after Featured rather than
// its old spot at the back. Groupings that have no authored devotions yet
// render as quiet, unlinked states; rows light up as the library grows. A
// season with a series opens onto it.
import type { Metadata } from 'next';
import Link from 'next/link';

import { getDocumentById } from '@/lib/catechisms';
import { catechismQuestionsAuthored, seriesForCatechism, seriesForSeason } from '@/lib/devotionSeries';
import {
  SEASONS, TOPICS, devotionsGroundedIn, scriptureDevotionsByBook,
} from '@/lib/devotions';
import { FeaturedSlot } from './FeaturedSlot';

export const metadata: Metadata = {
  title: 'Devotions',
  description:
    'A curated library of family devotions, each grounded in a range of '
    + 'Scripture, a topic, a catechism question, or a season of the church year.',
};

function RowLabel({ children }: { children: React.ReactNode }) {
  return (
    <div className="label-caps mt-1.5 border-t border-fill px-5 pt-3.5 pb-1.5 text-[9px] tracking-[0.14em] text-ink-3">
      {children}
    </div>
  );
}

// The catechisms the hub previews (mockup 15a) that have no run yet; their
// devotion runs are authored one per question / Lord's Day. WSC has a real
// run (turn 17) and renders from seriesForCatechism instead of this list.
const CATECHISM_ROWS = [
  { documentId: 'HC', unit: "One devotion per Lord's Day, 52 in all" },
];

export default function DevotionsPage() {
  const scriptureCount = devotionsGroundedIn('scripture').length;
  const bookCount = scriptureDevotionsByBook().size;
  const topicCounts = TOPICS.map((topic) => ({
    topic,
    count: devotionsGroundedIn('topic').filter((d) => d.grounding.kind === 'topic' && d.grounding.topic === topic.slug).length,
  }));
  const seasonCounts = SEASONS.map((season) => ({
    season,
    count: devotionsGroundedIn('season').filter((d) => d.grounding.kind === 'season' && d.grounding.season === season.slug).length,
  }));

  return (
    <div className="pb-12">
      <div className="px-6 pt-6 pb-4 text-center">
        <div className="label-caps text-[9.5px] tracking-[0.12em] text-ink-3">For Your Household</div>
        <h1 className="mt-1.5 mb-1 heading-page">Devotions</h1>
        <p className="m-0 font-body text-[12.5px] italic text-ink-3">
          Each one grounded in something specific — never generic filler
        </p>
      </div>

      <div className="label-caps px-5 pt-2 pb-1.5 text-[9px] tracking-[0.14em] text-ochre">
        Featured This Week
      </div>
      <FeaturedSlot />

      <RowLabel>By Confession &amp; Catechism</RowLabel>
      {(() => {
        const wscDoc = getDocumentById('WSC');
        const wscRun = seriesForCatechism('WSC');
        if (!wscDoc) return null;
        if (!wscRun) {
          return (
            <div className="border-t border-fill px-5 py-2.75 first-of-type:border-t-0">
              <div className="font-display text-[13.5px] font-semibold text-ink-2">{wscDoc.name}</div>
              <div className="font-body text-[12px] italic text-ink-3">
                {`One devotion per question, ${wscDoc.totalItems} in all — in preparation`}
              </div>
            </div>
          );
        }
        const authored = catechismQuestionsAuthored(wscRun);
        return (
          <Link
            href={`/devotions/${wscRun.slug}`}
            className="flex items-center justify-between border-t border-fill px-5 py-2.75 text-ink no-underline first-of-type:border-t-0"
          >
            <div>
              <div className="font-display text-[13.5px] font-semibold">{wscDoc.name}</div>
              <div className="font-body text-[12px] italic text-ink-3">
                {`Questions 1–${authored} of ${wscDoc.totalItems}, professed in order`}
              </div>
            </div>
            <span className="font-body text-ochre" aria-hidden="true">→</span>
          </Link>
        );
      })()}
      {CATECHISM_ROWS.map(({ documentId, unit }) => {
        const doc = getDocumentById(documentId);
        if (!doc) return null;
        return (
          <div key={documentId} className="border-t border-fill px-5 py-2.75 first-of-type:border-t-0">
            <div className="font-display text-[13.5px] font-semibold text-ink-2">{doc.name}</div>
            <div className="font-body text-[12px] italic text-ink-3">
              {unit}
              {' — in preparation'}
            </div>
          </div>
        );
      })}

      <RowLabel>By Scripture</RowLabel>
      <Link
        href="/devotions/scripture"
        className="flex items-center justify-between px-5 py-3 text-ink no-underline"
      >
        <div>
          <div className="mb-0.5 font-display text-[13.5px] font-semibold">
            Browse by Book, Chapter &amp; Verse
          </div>
          <div className="font-body text-[12px] italic text-ink-3">
            {scriptureCount === 1 ? '1 devotion' : `${scriptureCount} devotions`}
            {' across '}
            {bookCount === 1 ? '1 book' : `${bookCount} books`}
            , growing toward all 66
          </div>
        </div>
        <span className="font-body text-ochre" aria-hidden="true">→</span>
      </Link>

      <RowLabel>By Topic</RowLabel>
      <div className="flex flex-wrap gap-2 px-5 pt-2 pb-1">
        {topicCounts.map(({ topic, count }) => (count > 0 ? (
          <span key={topic.slug} className="rounded-full bg-fill px-4 py-2 font-body text-[12.5px] text-ink">
            {topic.name}
          </span>
        ) : (
          <span
            key={topic.slug}
            className="rounded-full border border-dotted border-muted px-4 py-2 font-body text-[12.5px] text-ink-3"
          >
            {topic.name}
          </span>
        )))}
      </div>
      <p className="m-0 px-5 pt-1.5 font-body text-[11px] italic text-muted">
        Devotions by topic are in preparation
      </p>

      <RowLabel>By Season</RowLabel>
      <div className="flex gap-2.5 px-5 pt-2 pb-1">
        {seasonCounts.map(({ season, count }) => {
          const series = seriesForSeason(season.slug);
          return series ? (
            <Link
              key={season.slug}
              href={`/devotions/${series.slug}`}
              className="flex-1 rounded-sm bg-fill px-3.5 py-3.5 text-ink no-underline"
            >
              <div className="mb-0.5 font-display text-[12.5px] font-semibold text-ink-2">{season.name}</div>
              <div className="font-body text-[11px] text-ink-3">
                {series.title}
                {' · '}
                {`a ${season.days}-part series`}
                {' '}
                <span className="text-ochre" aria-hidden="true">→</span>
              </div>
            </Link>
          ) : (
            <div key={season.slug} className="flex-1 rounded-sm bg-fill px-3.5 py-3.5">
              <div className="mb-0.5 font-display text-[12.5px] font-semibold text-ink-2">{season.name}</div>
              <div className="font-body text-[11px] text-ink-3">
                {count > 0
                  ? `${count} of ${season.days} devotions`
                  : `${season.days} daily devotions — in preparation`}
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
}
