import type { Metadata } from 'next';
import Link from 'next/link';
import { notFound } from 'next/navigation';

import { formatDate } from '@/lib/format';
import { listAuthors } from '@/lib/reflections';

interface Params {
  slug: string;
}

export const dynamicParams = false;

export async function generateStaticParams(): Promise<Params[]> {
  const authors = await listAuthors();
  return authors.map(({ slug }) => ({ slug }));
}

export async function generateMetadata(
  { params }: { params: Promise<Params> },
): Promise<Metadata> {
  const { slug } = await params;
  const author = (await listAuthors()).find((a) => a.slug === slug);
  if (!author) return {};
  return {
    title: author.name,
    description: `Reflections by ${author.name} on the confessions and catechisms.`,
    alternates: { canonical: `/authors/${slug}` },
  };
}

export default async function AuthorPage({ params }: { params: Promise<Params> }) {
  const { slug } = await params;
  const author = (await listAuthors()).find((a) => a.slug === slug);
  if (!author) notFound();

  return (
    <div className="pb-7">
      <div className="px-11 pt-6 text-center">
        <h1 className="mb-2.5 font-display text-xl font-semibold">{author.name}</h1>
        <p className="text-[13.5px] italic leading-relaxed text-ink-2">
          Writes on the Reformed confessions and their devotional use.
        </p>
      </div>

      <div className="mt-5 flex flex-col px-5">
        {author.reflections.map((post) => (
          <Link
            key={post.slug}
            href={`/reflections/${post.slug}`}
            className="border-t border-hairline py-[13px] text-ink no-underline"
          >
            <div className="mb-1 font-display text-[13.5px] font-semibold">{post.title}</div>
            <div className="label-caps mb-1 text-[9px] tracking-[0.1em] text-ink-3">
              {formatDate(post.date, 'short')}
            </div>
            {post.subtitle && (
              <div className="text-xs leading-relaxed text-ink-2">{post.subtitle}</div>
            )}
          </Link>
        ))}
      </div>
    </div>
  );
}
