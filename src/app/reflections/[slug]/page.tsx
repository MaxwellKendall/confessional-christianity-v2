import type { Metadata } from 'next';
import Link from 'next/link';
import { notFound } from 'next/navigation';

import { Markdown } from '@/components/Markdown';
import { entryPageLabel, entryQuoteLines } from '@/lib/entryDisplay';
import { formatDate } from '@/lib/format';
import { generateCanonicalEntryLink, parseConfessionId, truncateForMeta } from '@/lib/helpers';
import { getReflectionBySlug, loadReflections } from '@/lib/reflections';
import contentByIdJson from '../../../../dataMapping/content-by-id.json';
import type { ContentById } from '@/lib/domain';

const contentById = contentByIdJson as unknown as ContentById;

interface Params {
  slug: string;
}

export const dynamicParams = false;

export async function generateStaticParams(): Promise<Params[]> {
  const posts = await loadReflections();
  return posts.map(({ slug }) => ({ slug }));
}

export async function generateMetadata(
  { params }: { params: Promise<Params> },
): Promise<Metadata> {
  const { slug } = await params;
  const post = await getReflectionBySlug(slug);
  if (!post) return {};
  return {
    title: post.title,
    description: post.subtitle ?? truncateForMeta(post.body),
    alternates: { canonical: `/reflections/${slug}` },
  };
}

export default async function ReflectionPage({ params }: { params: Promise<Params> }) {
  const { slug } = await params;
  const post = await getReflectionBySlug(slug);
  if (!post) notFound();

  const entry = contentById[post.entryId];
  const entryHref = generateCanonicalEntryLink(post.entryId);
  const posts = await loadReflections();
  const siblings = post.series
    ? posts.filter((p) => p.series === post.series).sort((a, b) => (a.part ?? 0) - (b.part ?? 0))
    : posts.slice().reverse(); // oldest -> newest for prev/next reading order
  const index = siblings.findIndex((p) => p.slug === post.slug);
  const prev = siblings[index - 1] ?? null;
  const next = siblings[index + 1] ?? null;

  return (
    <article className="pb-6">
      <div className="px-11 pt-6 text-center">
        {post.series && (
          <div className="label-caps mb-3.5 text-[9.5px] text-ink-3">
            Series: {post.series}
            {post.part ? ` · Part ${post.part} of ${siblings.length}` : ''}
          </div>
        )}
        <h1 className="mb-2 font-display text-2xl font-semibold leading-[1.3]">{post.title}</h1>
        {post.subtitle && (
          <p className="mb-2.5 text-sm italic text-ink-2">{post.subtitle}</p>
        )}
        <div className="label-caps text-[10px] tracking-[0.14em] text-ink-3">
          {post.author && post.authorSlug ? (
            <Link href={`/authors/${post.authorSlug}`} className="text-ink-3 no-underline">
              {post.author}
            </Link>
          ) : null}
          {post.author && post.date ? ' · ' : ''}
          {formatDate(post.date)}
        </div>
      </div>

      {entry && entryHref && (
        <Link
          href={entryHref}
          className="mx-5 mt-6 block rounded-[2px] bg-fill px-5 py-[22px] text-inherit no-underline"
        >
          <div className="label-caps mb-2.5 text-center text-[9.5px] text-ink-3">
            {parseConfessionId(entry.id.split('-')[0])} · {entryPageLabel(entry)}
          </div>
          <blockquote className="m-0 text-center font-body text-[17px] italic leading-[1.55] text-ink">
            {entryQuoteLines(entry).map((line, i) => (
              <span key={i}>
                {i > 0 && <br />}
                {line}
              </span>
            ))}
          </blockquote>
        </Link>
      )}

      <div className="px-5 pt-6">
        <Markdown source={post.body} />
      </div>

      <div className="mx-5 mt-7 flex items-center justify-between border-t border-hairline pt-4 label-caps text-[10px] tracking-[0.1em]">
        {prev ? (
          <Link href={`/reflections/${prev.slug}`} className="dotted-link text-ink">
            ← {prev.part ? `Part ${prev.part}` : prev.title}
          </Link>
        ) : (
          <span className="text-muted">← Prev</span>
        )}
        {next ? (
          <Link href={`/reflections/${next.slug}`} className="dotted-link text-ink">
            {next.part ? `Part ${next.part}: ${next.title}` : next.title} →
          </Link>
        ) : (
          <span className="text-muted">Next →</span>
        )}
      </div>
    </article>
  );
}
