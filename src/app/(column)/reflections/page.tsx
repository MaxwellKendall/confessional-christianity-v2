import type { Metadata } from 'next';
import Link from 'next/link';

import { formatDate } from '@/lib/format';
import { loadReflections, type Reflection } from '@/lib/reflections';

export const metadata: Metadata = {
  title: 'Reflections',
  description: 'Essays on the confessions and catechisms and their devotional use.',
  alternates: { canonical: '/reflections' },
};

function ReflectionRow({ post }: { post: Reflection }) {
  return (
    <Link
      href={`/reflections/${post.slug}`}
      className="border-t border-hairline py-3 text-ink no-underline"
    >
      <div className="mb-1 font-display text-[13.5px] font-semibold">
        {post.part ? `Part ${post.part}: ${post.title}` : post.title}
      </div>
      <div className="label-caps mb-1 text-[9px] tracking-[0.1em] text-ink-3">
        {[post.author, formatDate(post.date, 'short')].filter(Boolean).join(' · ')}
      </div>
      {post.subtitle && (
        <div className="text-xs leading-relaxed text-ink-2">{post.subtitle}</div>
      )}
    </Link>
  );
}

export default async function ReflectionsPage() {
  const posts = await loadReflections();
  const seriesNames = Array.from(
    new Set(posts.filter((p) => p.series).map((p) => p.series as string)),
  );
  const standalone = posts.filter((p) => !p.series);

  return (
    <div className="pb-7">
      <div className="px-5 pt-6 text-center">
        <h1 className="font-display text-xl font-semibold">Reflections</h1>
      </div>

      {seriesNames.map((series) => (
        <div key={series} className="px-5 pt-6">
          <div className="label-caps mb-1.5 text-[9.5px] tracking-[0.1em] text-ink-3">
            Series · {series}
          </div>
          <div className="flex flex-col">
            {posts
              .filter((p) => p.series === series)
              .sort((a, b) => (a.part ?? 0) - (b.part ?? 0))
              .map((post) => <ReflectionRow key={post.slug} post={post} />)}
          </div>
        </div>
      ))}

      {standalone.length > 0 && (
        <div className="px-5 pt-5">
          {seriesNames.length > 0 && (
            <div className="label-caps mb-1.5 text-[9.5px] tracking-[0.1em] text-ink-3">
              Standalone Essays
            </div>
          )}
          <div className="flex flex-col">
            {standalone.map((post) => <ReflectionRow key={post.slug} post={post} />)}
          </div>
        </div>
      )}

      {posts.length === 0 && (
        <p className="px-8 pt-8 text-center text-[13px] italic text-ink-2">
          Essays are on their way.
        </p>
      )}
    </div>
  );
}
