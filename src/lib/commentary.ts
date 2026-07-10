import path from 'path';
import { promises as fs } from 'fs';
import matter from 'gray-matter';

import type { Commentary } from './domain';

const COMMENTARY_DIR = path.join(process.cwd(), 'content', 'commentary');

const toDateString = (d: unknown): string | null => {
  if (!d) return null;
  if (d instanceof Date) return d.toISOString().slice(0, 10);
  return String(d);
};

const isEnoent = (err: unknown): boolean => (
  typeof err === 'object' && err !== null && (err as NodeJS.ErrnoException).code === 'ENOENT'
);

// Loads the optional long-form commentary / reflection post for a single
// entry id (e.g. "WSC-1", "WCoF-1-2"). Returns null when no post exists for
// that entry, so entries without commentary render exactly as before. Read at
// build time in static RSC, so there are no serverless file-tracing concerns.
export const loadCommentary = async (entryId: string): Promise<Commentary | null> => {
  try {
    const raw = await fs.readFile(path.join(COMMENTARY_DIR, `${entryId}.md`), 'utf8');
    const { data, content } = matter(raw);
    return {
      title: data.title || null,
      subtitle: data.subtitle || null,
      author: data.author || null,
      date: toDateString(data.date),
      body: content,
    };
  } catch (err) {
    if (isEnoent(err)) return null;
    throw err;
  }
};

// Returns the list of entry ids that have a commentary post, for building the
// reflections index and the sitemap.
export const listCommentaryIds = async (): Promise<string[]> => {
  try {
    const files = await fs.readdir(COMMENTARY_DIR);
    return files.filter((f) => f.endsWith('.md')).map((f) => f.replace(/\.md$/, ''));
  } catch (err) {
    if (isEnoent(err)) return [];
    throw err;
  }
};
