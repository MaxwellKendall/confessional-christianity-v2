// Reflections are the long-form essays (v1 "commentary"), still authored as
// content/commentary/<entryId>.md but surfaced at /reflections/[slug] in v2.
// The library entry a post is written on stays canonical and clean; the essay
// gets its own URL, and the entry links to it with the † marker (PRD §10).
import path from 'path';
import { promises as fs } from 'fs';
import matter from 'gray-matter';

const COMMENTARY_DIR = path.join(process.cwd(), 'content', 'commentary');

export interface Reflection {
  /** URL slug for /reflections/[slug]; frontmatter `slug` or kebab-cased title. */
  slug: string;
  /** The library entry the essay is written on, e.g. "WSC-1". */
  entryId: string;
  title: string;
  subtitle: string | null;
  author: string | null;
  authorSlug: string | null;
  /** ISO date string (YYYY-MM-DD) or null. */
  date: string | null;
  /** Optional series name + part for grouped essays. */
  series: string | null;
  part: number | null;
  /** Markdown body. */
  body: string;
}

export const slugify = (value: string): string => value
  .toLowerCase()
  .replace(/['’]/g, '')
  .replace(/[^a-z0-9]+/g, '-')
  .replace(/^-+|-+$/g, '');

const toDateString = (d: unknown): string | null => {
  if (!d) return null;
  if (d instanceof Date) return d.toISOString().slice(0, 10);
  return String(d);
};

const isEnoent = (err: unknown): boolean => (
  typeof err === 'object' && err !== null && (err as NodeJS.ErrnoException).code === 'ENOENT'
);

const parseReflection = (entryId: string, raw: string): Reflection => {
  const { data, content } = matter(raw);
  const title = data.title || entryId;
  const author = data.author || null;
  return {
    slug: data.slug || slugify(title),
    entryId,
    title,
    subtitle: data.subtitle || null,
    author,
    authorSlug: author ? slugify(author) : null,
    date: toDateString(data.date),
    series: data.series || null,
    part: typeof data.part === 'number' ? data.part : null,
    body: content,
  };
};

// newest first, the reflections-index order.
export const loadReflections = async (): Promise<Reflection[]> => {
  let files: string[];
  try {
    files = await fs.readdir(COMMENTARY_DIR);
  } catch (err) {
    if (isEnoent(err)) return [];
    throw err;
  }
  const posts = await Promise.all(
    files
      .filter((f) => f.endsWith('.md'))
      .map(async (f) => {
        const raw = await fs.readFile(path.join(COMMENTARY_DIR, f), 'utf8');
        return parseReflection(f.replace(/\.md$/, ''), raw);
      }),
  );
  return posts.sort((a, b) => (b.date ?? '').localeCompare(a.date ?? ''));
};

export const getReflectionBySlug = async (slug: string): Promise<Reflection | null> => {
  const posts = await loadReflections();
  return posts.find((p) => p.slug === slug) ?? null;
};

export const getReflectionByEntryId = async (entryId: string): Promise<Reflection | null> => {
  const posts = await loadReflections();
  return posts.find((p) => p.entryId === entryId) ?? null;
};

export interface Author {
  slug: string;
  name: string;
  reflections: Reflection[];
}

export const listAuthors = async (): Promise<Author[]> => {
  const posts = await loadReflections();
  const bySlug = new Map<string, Author>();
  posts.forEach((post) => {
    if (!post.author || !post.authorSlug) return;
    const existing = bySlug.get(post.authorSlug);
    if (existing) {
      existing.reflections.push(post);
    } else {
      bySlug.set(post.authorSlug, {
        slug: post.authorSlug,
        name: post.author,
        reflections: [post],
      });
    }
  });
  return Array.from(bySlug.values());
};
