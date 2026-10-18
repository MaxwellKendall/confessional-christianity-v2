'use server';

import { cookies } from 'next/headers';
import { redirect } from 'next/navigation';

import {
  ADMIN_COOKIE, SESSION_TTL_SECONDS, adminAccess, createSessionToken, isAdminToken, passwordMatches,
} from '@/lib/admin/session';
import { catechismSeriesParts } from '@/lib/admin/catechismParts';
import { getDevotionStore, type SaveResult } from '@/lib/admin/store';
import { citationToOsis, parseOsisBibleReference } from '@/lib/bible';
import type { Devotion } from '@/lib/devotions';
import type { DevotionSeries, SeriesPart } from '@/lib/devotionSeries';
import { validateDevotion, validateSeries, type SeriesLink } from '@/lib/devotionValidation';

/** Server actions are public POST endpoints whatever proxy.ts matches, so
 * each one checks the session itself. */
const requireAdmin = async (): Promise<void> => {
  const token = (await cookies()).get(ADMIN_COOKIE)?.value;
  if (!(await isAdminToken(token))) throw new Error('Not signed in to the admin.');
};

export interface LoginState {
  error: string | null;
}

export async function login(_prev: LoginState, form: FormData): Promise<LoginState> {
  if (adminAccess() !== 'password') return { error: 'The admin has no password configured.' };
  if (!(await passwordMatches(String(form.get('password') ?? '')))) {
    return { error: 'That password is not right.' };
  }
  (await cookies()).set(ADMIN_COOKIE, await createSessionToken(), {
    httpOnly: true,
    secure: process.env.NODE_ENV === 'production',
    sameSite: 'lax',
    path: '/admin',
    maxAge: SESSION_TTL_SECONDS,
  });
  const next = String(form.get('next') ?? '');
  // only ever bounce back inside the admin
  redirect(next.startsWith('/admin/') && !next.startsWith('/admin/login') ? next : '/admin/devotions');
}

export async function logout(): Promise<void> {
  (await cookies()).delete({ name: ADMIN_COOKIE, path: '/admin' });
  redirect('/admin/login');
}

export type SaveResponse =
  | { ok: true; result: SaveResult }
  | { ok: false; errors: string[] };

export async function saveDevotion(input: {
  devotion: Devotion;
  link: SeriesLink | null;
  isNew: boolean;
}): Promise<SaveResponse> {
  await requireAdmin();
  const setup = getDevotionStore();
  if (!setup.ok) return { ok: false, errors: [setup.reason] };
  const { store } = setup;
  const { devotion, link, isNew } = input;

  try {
    // a new slug must be free; an existing one must exist (slugs never change)
    const takenSlugs = isNew
      ? await store.takenSlugs()
      : (await store.series()).map((s) => s.slug);
    if (!isNew && !(await store.load(devotion.slug))) {
      return { ok: false, errors: [`there is no devotion "${devotion.slug}" to update`] };
    }
    const errors = validateDevotion(devotion, { takenSlugs });
    if (errors.length) return { ok: false, errors };
    return { ok: true, result: await store.save({ devotion, link, isNew }) };
  } catch (error) {
    return { ok: false, errors: [error instanceof Error ? error.message : String(error)] };
  }
}

export async function saveSeries(input: {
  series: DevotionSeries;
  isNew: boolean;
}): Promise<SaveResponse> {
  await requireAdmin();
  const setup = getDevotionStore();
  if (!setup.ok) return { ok: false, errors: [setup.reason] };
  const { store } = setup;
  const { series, isNew } = input;

  try {
    let otherSeries: DevotionSeries[];
    let takenSlugs: string[] = [];
    if (isNew) {
      [takenSlugs, otherSeries] = await Promise.all([store.takenSlugs(), store.series()]);
    } else {
      const loaded = await store.loadSeries(series.slug);
      if (!loaded) return { ok: false, errors: [`there is no series "${series.slug}" to update`] };
      otherSeries = loaded.otherSeries;
    }
    const errors = validateSeries(series, { takenSlugs, otherSeries });
    if (errors.length) return { ok: false, errors };
    return { ok: true, result: await store.saveSeries({ series, isNew }) };
  } catch (error) {
    return { ok: false, errors: [error instanceof Error ? error.message : String(error)] };
  }
}

export async function setFeaturedDevotion(slug: string): Promise<SaveResponse> {
  await requireAdmin();
  const setup = getDevotionStore();
  if (!setup.ok) return { ok: false, errors: [setup.reason] };
  try {
    return { ok: true, result: await setup.store.setFeatured(slug) };
  } catch (error) {
    return { ok: false, errors: [error instanceof Error ? error.message : String(error)] };
  }
}

/** Closes a draft's PR and deletes its branch, then returns to the list. */
export async function discardDraft(kind: 'devotion' | 'series', slug: string): Promise<{ error: string }> {
  await requireAdmin();
  const setup = getDevotionStore();
  if (!setup.ok) return { error: setup.reason };
  try {
    await setup.store.discard(kind, slug);
  } catch (error) {
    return { error: error instanceof Error ? error.message : String(error) };
  }
  redirect(kind === 'devotion' ? '/admin/devotions' : '/admin/series');
}

/** One part per top-level entry of a document, for prefilling a new run. */
export async function prefillCatechismParts(documentId: string): Promise<SeriesPart[]> {
  await requireAdmin();
  return catechismSeriesParts(documentId);
}

export interface ScriptureLookup {
  citation: string;
  osis: string;
  /** null when the ESV key isn't configured or the passage didn't resolve. */
  text: string | null;
  error?: string;
}

/** Resolves a typed citation ("Psalm 67:3") to its OSIS id and ESV text, in
 * the shape the devotion files store: verse numbers inline, the ESV's own
 * line breaks kept for poetry. */
export async function lookupScripture(citation: string): Promise<ScriptureLookup> {
  await requireAdmin();
  const osis = citationToOsis(citation);
  if (!osis) return { citation, osis: '', text: null, error: `Couldn't read "${citation}" as a Bible reference.` };
  const canonical = parseOsisBibleReference(osis);
  const key = process.env.ESV_API_KEY;
  if (!key) return { citation: canonical, osis, text: null, error: 'ESV_API_KEY is not set, so the text has to be pasted in.' };

  const params = new URLSearchParams({
    q: canonical,
    'include-passage-references': 'false',
    'include-verse-numbers': 'true',
    'include-footnotes': 'false',
    'include-headings': 'false',
    'include-short-copyright': 'false',
    'line-length': '0',
  });
  const response = await fetch(`https://api.esv.org/v3/passage/text/?${params}`, {
    headers: { Authorization: `Token ${key}` },
    cache: 'no-store',
  });
  if (!response.ok) return { citation: canonical, osis, text: null, error: `The ESV API answered ${response.status}.` };
  const data = (await response.json()) as { passages?: string[] };
  const raw = data.passages?.[0]?.trim();
  if (!raw) return { citation: canonical, osis, text: null, error: 'The ESV API returned no passage.' };
  const text = raw
    .replace(/\[(\d+)\]\s*/g, '$1 ')
    .replace(/\n{3,}/g, '\n\n')
    .replace(/^ {2,}/gm, ' ');
  return { citation: canonical, osis, text };
}
