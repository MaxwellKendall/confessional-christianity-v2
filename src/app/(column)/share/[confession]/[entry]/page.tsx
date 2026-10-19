// Where a shared quote lands. Someone tapped a link a friend sent: show
// them the quote first, exactly as shared and set like the library page,
// then the Scripture standing behind it (the point of a confession), then a
// way into the rest — the passage in context, and for a catechism, teaching
// it at home. Rendered per URL (the selection lives in the query) and kept
// out of search indexes; the library entry stays the canonical page.
import type { Metadata } from 'next';
import { headers } from 'next/headers';
import Link from 'next/link';
import { notFound } from 'next/navigation';

import { ShareActions } from '@/components/ShareActions';
import { PROGRAMS } from '@/lib/programs';
import { parseSelection, shareImagePath, shareText } from '@/lib/share';
import { excerpt, resolveShare, shareScripture } from '@/lib/shareContent';

interface Params {
  confession: string;
  entry: string;
}
type SearchParams = Record<string, string | string[] | undefined>;

export async function generateMetadata(
  { params, searchParams }: { params: Promise<Params>; searchParams: Promise<SearchParams> },
): Promise<Metadata> {
  const { confession, entry } = await params;
  const share = await resolveShare(confession, entry, parseSelection(await searchParams));
  if (!share) return {};
  const { quote } = share;
  const title = `“${excerpt(quote.quote, 90)}” — ${share.source}`;
  const description = [
    quote.question ? `Q. ${quote.question}` : null,
    quote.refs.length ? `With ${quote.refs.map((r) => r.citation).slice(0, 3).join(', ')}${quote.refs.length > 3 ? ' and more' : ''}.` : null,
  ].filter(Boolean).join(' ') || share.source;
  // absolute against the host serving this request, so previews unfurl
  // from whichever domain the link was shared on (production, a preview
  // deployment) rather than a hardcoded one
  const h = await headers();
  const host = h.get('x-forwarded-host') ?? h.get('host');
  const origin = host ? `${h.get('x-forwarded-proto') ?? 'https'}://${host}` : '';
  const image = {
    url: `${origin}${shareImagePath(share.path, 'og')}`,
    width: 1200,
    height: 630,
    alt: `${quote.question ? `Q. ${quote.question} A. ` : ''}${quote.quote} — ${share.source}`,
  };
  return {
    title: { absolute: title },
    description,
    alternates: { canonical: share.context.split('#')[0] },
    robots: { index: false, follow: true },
    openGraph: { type: 'article', title, description, url: `${origin}${share.path}`, images: [image], siteName: 'Confessional Christianity' },
    twitter: { card: 'summary_large_image', title, description, images: [image.url] },
  };
}

export default async function SharePage(
  { params, searchParams }: { params: Promise<Params>; searchParams: Promise<SearchParams> },
) {
  const { confession, entry } = await params;
  const share = await resolveShare(confession, entry, parseSelection(await searchParams));
  if (!share) notFound();

  const { quote, page } = share;
  const scripture = await shareScripture(quote);
  const program = PROGRAMS.find((p) => p.contentId === page.documentId);
  const lead = scripture.find((s) => s.text);

  return (
    <div className="pb-10">
      <div className="px-5 pt-5 label-caps text-[9.5px] tracking-[0.1em] text-ink-3">
        <Link href="/library" className="dotted-link text-ink-3">Library</Link>
        {' / '}
        <Link href={`/library/${confession}`} className="text-ink-3 no-underline">{page.documentTitle}</Link>
      </div>

      <figure className="mx-5 mt-5 mb-0 rounded-sm border border-hairline bg-white px-7 pt-7 pb-6 text-center shadow-frame sm:px-10">
        <div className="label-caps mb-4 text-[9.5px] tracking-[0.14em] text-ochre">{share.label}</div>
        <blockquote className="m-0 font-body text-[19px] italic leading-[1.55] text-ink sm:text-[21px]">
          {quote.question && (
            <p className="m-0 mb-2 font-display text-[15px] not-italic font-semibold leading-snug text-ink-2 sm:text-[16px]">
              Q. {quote.question}
            </p>
          )}
          <p className="m-0">{quote.question ? `A. ${quote.quote}` : `“${quote.quote}”`}</p>
        </blockquote>
        <figcaption className="label-caps mt-5 text-[9.5px] tracking-[0.1em] text-ink-3">
          {page.documentTitle}
        </figcaption>
      </figure>

      <div className="mx-5 mt-5">
        <ShareActions
          target={{
            path: share.path,
            title: share.source,
            text: shareText(quote, { source: share.source, scripture: lead ? { citation: lead.citation, text: excerpt(lead.text!, 280) } : null }),
          }}
        />
      </div>

      <div className="mx-5 mt-3 text-center">
        <Link href={share.context} className="label-caps dotted-link text-[10px] tracking-[0.1em] text-ink">
          Read it in context →
        </Link>
      </div>

      {scripture.length > 0 && (
        <section className="mx-5 mt-8 border-t border-hairline pt-5">
          <h2 className="label-caps m-0 mb-1 text-[9.5px] font-normal tracking-[0.12em] text-ink-3">
            The Scripture behind it
          </h2>
          <p className="m-0 mb-4 font-body text-[12.5px] italic text-ink-3">
            The proof texts the {page.documentTitle} gives for {quote.selection.kind === 'entry' ? 'these words' : 'this part'}.
          </p>
          <div className="flex flex-col gap-4">
            {scripture.map((ref) => (
              <div key={ref.osis} className="border-l border-hairline pl-3.5">
                {ref.text && <p className="m-0 font-body text-[14px] italic leading-relaxed text-ink-2">{ref.text}</p>}
                <Link href={`/scripture/${ref.osis}`} className="label-caps dotted-link mt-1.5 inline-block text-[9.5px] tracking-[0.08em] text-ink">
                  {ref.citation}{ref.text ? ' (ESV)' : ''} — across the confessions →
                </Link>
              </div>
            ))}
          </div>
          {scripture.some((s) => s.text) && (
            <p className="m-0 mt-5 text-[11px] text-muted">
              Scripture quotations are from the ESV® Bible, copyright © 2001 by Crossway. Used by permission.
            </p>
          )}
        </section>
      )}

      <section className="mx-5 mt-8 rounded-sm bg-fill px-5 py-5 text-center">
        {program ? (
          <>
            <p className="m-0 font-display text-[14px] font-semibold text-ink">Teach it at home, one question at a time</p>
            <p className="m-0 mt-1 font-body text-[12.5px] italic text-ink-3">
              The {program.shortTitle}, with its Scripture and a prayer for each question, paced for your family.
            </p>
            <Link href={`/programs/${program.slug}`} className="action-button mt-3.5 inline-block">
              Start the {program.shortTitle}
            </Link>
          </>
        ) : (
          <>
            <p className="m-0 font-display text-[14px] font-semibold text-ink">Read the whole {page.documentTitle}</p>
            <Link href={`/library/${confession}`} className="action-button mt-3.5 inline-block">
              Open it in the Library
            </Link>
          </>
        )}
      </section>
    </div>
  );
}
