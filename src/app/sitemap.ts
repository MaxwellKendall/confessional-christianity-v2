import type { MetadataRoute } from 'next';

import { confessionSlugs } from '@/lib/confessionContent';
import { getAllEntryParams } from '@/lib/library';
import { getAllDevotions } from '@/lib/devotions';
import { listAuthors, loadReflections } from '@/lib/reflections';
import { getAllScriptureParams } from '@/lib/scripture';
import { PROGRAMS } from '@/lib/programs';

const BASE = 'https://confessionalchristianity.com';

// Fully static: every canonical reading URL the redirect map points at, plus
// the program landing pages. Transient/auth surfaces (search, session,
// onboarding, invites) are intentionally absent.
export default async function sitemap(): Promise<MetadataRoute.Sitemap> {
  const [entryParams, reflections, authors, scriptureParams] = await Promise.all([
    getAllEntryParams(),
    loadReflections(),
    listAuthors(),
    getAllScriptureParams(),
  ]);

  return [
    { url: `${BASE}/`, changeFrequency: 'weekly', priority: 1 },
    { url: `${BASE}/programs`, changeFrequency: 'weekly', priority: 0.9 },
    ...PROGRAMS.map(({ slug }) => ({
      url: `${BASE}/programs/${slug}`,
      changeFrequency: 'weekly' as const,
      priority: 0.9,
    })),
    { url: `${BASE}/devotions`, changeFrequency: 'weekly', priority: 0.8 },
    { url: `${BASE}/devotions/scripture`, changeFrequency: 'weekly', priority: 0.7 },
    ...getAllDevotions().map(({ slug }) => ({
      url: `${BASE}/devotions/${slug}`,
      changeFrequency: 'monthly' as const,
      priority: 0.7,
    })),
    { url: `${BASE}/library`, changeFrequency: 'monthly', priority: 0.9 },
    ...confessionSlugs.map((slug) => ({
      url: `${BASE}/library/${slug}`,
      changeFrequency: 'monthly' as const,
      priority: 0.8,
    })),
    ...entryParams.map(({ confession, entry }) => ({
      url: `${BASE}/library/${confession}/${entry}`,
      changeFrequency: 'yearly' as const,
      priority: 0.7,
    })),
    { url: `${BASE}/reflections`, changeFrequency: 'weekly', priority: 0.8 },
    ...reflections.map(({ slug }) => ({
      url: `${BASE}/reflections/${slug}`,
      changeFrequency: 'monthly' as const,
      priority: 0.7,
    })),
    ...authors.map(({ slug }) => ({
      url: `${BASE}/authors/${slug}`,
      changeFrequency: 'monthly' as const,
      priority: 0.5,
    })),
    ...scriptureParams.map(({ osis }) => ({
      url: `${BASE}/scripture/${osis}`,
      changeFrequency: 'yearly' as const,
      priority: 0.4,
    })),
  ];
}
