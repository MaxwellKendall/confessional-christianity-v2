// A single devotion's landing page (mockup 15c): what's inside, why it's
// grounded this way, and a Begin that hands off to the same eight-step
// shell Family Worship uses. The catechism step previews as "today's
// question" — which question that is depends on the household's track,
// not the devotion.
import type { Metadata } from 'next';
import Link from 'next/link';
import { notFound } from 'next/navigation';

import { getAllDevotions, getDevotion, groundingLabel } from '@/lib/devotions';
import { stepDetail } from '@/lib/worship';

export const dynamicParams = false;

export function generateStaticParams(): { slug: string }[] {
  return getAllDevotions().map(({ slug }) => ({ slug }));
}

export async function generateMetadata(
  { params }: { params: Promise<{ slug: string }> },
): Promise<Metadata> {
  const { slug } = await params;
  const devotion = getDevotion(slug);
  if (!devotion) return {};
  return { title: devotion.title, description: devotion.summary };
}

export default async function DevotionPage(
  { params }: { params: Promise<{ slug: string }> },
) {
  const { slug } = await params;
  const devotion = getDevotion(slug);
  if (!devotion) notFound();

  return (
    <div className="flex min-h-[calc(100dvh-7rem)] flex-col">
      <div className="flex-1 px-7 pt-7 pb-2.5 text-center">
        <div className="label-caps mb-2.5 text-[9px] tracking-[0.14em] text-ochre">
          Grounded in {groundingLabel(devotion.grounding)}
        </div>
        <h1 className="m-0 mb-2.5 heading-page">{devotion.title}</h1>
        <p className="m-0 mb-5.5 font-body text-[13px] italic leading-[1.7] text-ink-2">
          {devotion.description}
        </p>
        <div className="mx-auto mb-5.5 h-px w-9 bg-hairline" aria-hidden="true" />

        <ol className="m-0 list-none p-0 text-left">
          {devotion.steps.map((step, i) => {
            const detail = step.elements[0]?.type === 'catechism'
              ? 'today’s question'
              : stepDetail(step);
            return (
              <li
                key={step.role}
                className={`flex items-center gap-3 py-2.5 ${i < devotion.steps.length - 1 ? 'border-b border-fill' : ''}`}
              >
                <span className="w-5 shrink-0 font-display text-[10px] text-ochre">{i + 1}</span>
                <span className="font-body text-[13px] text-ink">
                  {step.role}
                  {detail ? ` — ${detail}` : ''}
                </span>
              </li>
            );
          })}
        </ol>
      </div>

      <div className="border-t border-hairline px-6 pt-3.5 pb-9">
        <Link href={`/devotions/${devotion.slug}/worship`} className="action-button">
          Begin This Devotion
        </Link>
      </div>
    </div>
  );
}
