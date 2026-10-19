// Server-side ESV passage fetch — the one place the ESV key is used. The
// /api/esv proxy, share pages, and share images all read through here, so
// every surface asks the API for passages the same way and shares Next's
// fetch cache (passages never change).
import { parseOsisBibleReference } from './bible';

export interface EsvOptions {
  /** Keep the ESV's own paragraph breaks and poetry indentation (a full
   * chapter read); otherwise whitespace collapses to one flowing line. */
  formatted?: boolean;
}

/** The passage text for an OSIS ref, or null when the key isn't configured
 * or the API can't resolve it (callers degrade to the citation alone). */
export const fetchEsvPassage = async (osis: string, { formatted = false }: EsvOptions = {}): Promise<string | null> => {
  const key = process.env.ESV_API_KEY;
  if (!key) return null;

  const params = new URLSearchParams({
    q: parseOsisBibleReference(osis),
    'include-passage-references': 'false',
    'include-verse-numbers': 'false',
    'include-footnotes': 'false',
    'include-headings': 'false',
    'include-short-copyright': 'false',
    // line-length defaults to a fixed column width that hard-wraps with its
    // own \n's — pointless (and wrong) once a client reflows the text itself
    ...(formatted ? { 'line-length': '0' } : {}),
  });

  try {
    const response = await fetch(`https://api.esv.org/v3/passage/text/?${params}`, {
      headers: { Authorization: `Token ${key}` },
      next: { revalidate: 60 * 60 * 24 * 30 },
    });
    if (!response.ok) return null;
    const data = (await response.json()) as { passages?: string[] };
    const raw = data.passages?.[0]?.trim() ?? null;
    if (!raw) return null;
    return formatted ? raw.replace(/\n{3,}/g, '\n\n') : raw.replace(/\s+/g, ' ');
  } catch {
    return null;
  }
};
