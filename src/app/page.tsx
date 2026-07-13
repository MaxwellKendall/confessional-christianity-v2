import { HomeClient, type HomeReflection } from '@/components/HomeClient';
import { formatDate } from '@/lib/format';
import { loadReflections } from '@/lib/reflections';

// The homepage's job is getting a parent into today's session (PRD §8) —
// no account, no held screen, just a single button in.
export default async function Home() {
  const posts = await loadReflections();
  const reflections: HomeReflection[] = posts.slice(0, 2).map((post) => ({
    slug: post.slug,
    title: post.title,
    author: post.author,
    dateShort: formatDate(post.date, 'short'),
  }));

  return <HomeClient reflections={reflections} />;
}
