// Curated resources per catechism question (mockup 10a), authored as
// frontmatter markdown under content/resources/<entryId>/ — one file per
// resource, same gray-matter pattern as reflections.ts. A resource either
// points off-app (url: Spotify, YouTube, Amazon, a publication) or, for
// original writing, at the reflection that is its in-app reader
// (reflection: <slug> → /reflections/[slug]).
import path from 'path';
import { promises as fs } from 'fs';
import matter from 'gray-matter';

import { isResourceKind, RESOURCE_KINDS, type ResourceKind } from './resourceKinds';

const RESOURCES_DIR = path.join(process.cwd(), 'content', 'resources');

export interface Resource {
  /** The catechism entry the resource is curated for, e.g. "WSC-1". */
  entryId: string;
  kind: ResourceKind;
  title: string;
  /** The row's meta line, e.g. "Spotify · Sovereign Grace Music". */
  meta: string;
  /** External destination — required for every kind except original. */
  url: string | null;
  /** The in-app reader target for original writing: a reflection slug. */
  reflectionSlug: string | null;
  /** Authored sort position within the entry's list. */
  order: number;
}

const isEnoent = (err: unknown): boolean => (
  typeof err === 'object' && err !== null && (err as NodeJS.ErrnoException).code === 'ENOENT'
);

// A file that doesn't amount to a presentable row (unknown kind, no title, or
// no destination of either flavor) is authoring in progress, not content —
// it's skipped rather than rendered broken.
const parseResource = (entryId: string, raw: string): Resource | null => {
  const { data } = matter(raw);
  if (!isResourceKind(data.kind) || !data.title) return null;
  const url = typeof data.url === 'string' && data.url ? data.url : null;
  const reflectionSlug = typeof data.reflection === 'string' && data.reflection
    ? data.reflection
    : null;
  if (data.kind === 'original' ? !reflectionSlug : !url) return null;
  return {
    entryId,
    kind: data.kind,
    title: String(data.title),
    meta: data.meta ? String(data.meta) : '',
    url,
    reflectionSlug,
    order: typeof data.order === 'number' ? data.order : Number.MAX_SAFE_INTEGER,
  };
};

const byAuthoredOrder = (a: Resource, b: Resource): number => (
  a.order - b.order
  || RESOURCE_KINDS.indexOf(a.kind) - RESOURCE_KINDS.indexOf(b.kind)
  || a.title.localeCompare(b.title)
);

/** Every resource curated for one entry, in authored order; [] when none. */
export const loadResources = async (entryId: string): Promise<Resource[]> => {
  let files: string[];
  try {
    files = await fs.readdir(path.join(RESOURCES_DIR, entryId));
  } catch (err) {
    if (isEnoent(err)) return [];
    throw err;
  }
  const resources = await Promise.all(
    files
      .filter((f) => f.endsWith('.md'))
      .map(async (f) => {
        const raw = await fs.readFile(path.join(RESOURCES_DIR, entryId, f), 'utf8');
        return parseResource(entryId, raw);
      }),
  );
  return resources
    .filter((r): r is Resource => r !== null)
    .sort(byAuthoredOrder);
};

export const hasResources = async (entryId: string): Promise<boolean> => (
  (await loadResources(entryId)).length > 0
);
