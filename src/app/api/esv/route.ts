import { NextRequest, NextResponse } from 'next/server';

import { parseOsisBibleReference } from '@/lib/bible';

// Fetches proof-text scripture for a session step. Server-side only: the ESV
// key never reaches the browser (unlike v1's NEXT_PUBLIC_ usage). Responses
// are cacheable — passages never change.
export async function GET(request: NextRequest) {
  const osis = request.nextUrl.searchParams.get('osis');
  if (!osis) {
    return NextResponse.json({ error: 'osis required' }, { status: 400 });
  }
  // Proof texts (ScriptureView, DevotionWorshipView) render as a single
  // flowing quote, so their whitespace is collapsed to one line below.
  // A full-chapter read (ReadingChapterView) wants the ESV API's own
  // paragraph breaks and poetry indentation intact instead.
  const formatted = request.nextUrl.searchParams.get('formatted') === 'true';

  const citation = parseOsisBibleReference(osis);
  const key = process.env.ESV_API_KEY;
  if (!key) {
    // degrade to citation-only rendering
    return NextResponse.json({ citation, text: null });
  }

  const params = new URLSearchParams({
    q: citation,
    'include-passage-references': 'false',
    'include-verse-numbers': 'false',
    'include-footnotes': 'false',
    'include-headings': 'false',
    'include-short-copyright': 'false',
    // line-length defaults to a fixed column width that hard-wraps with
    // its own \n's — pointless (and wrong) once a client reflows the text
    // itself, so disable it for the formatted case. indent-paragraphs and
    // indent-poetry stay at their (already-on) defaults; there's just
    // nothing left downstream to strip them out.
    ...(formatted ? { 'line-length': '0' } : {}),
  });

  const response = await fetch(`https://api.esv.org/v3/passage/text/?${params}`, {
    headers: { Authorization: `Token ${key}` },
    next: { revalidate: 60 * 60 * 24 * 30 },
  });

  if (!response.ok) {
    return NextResponse.json({ citation, text: null });
  }

  const data = (await response.json()) as { passages?: string[] };
  const raw = data.passages?.[0]?.trim() ?? null;
  const text = formatted ? (raw?.replace(/\n{3,}/g, '\n\n') ?? null) : (raw?.replace(/\s+/g, ' ') ?? null);
  return NextResponse.json({ citation, text });
}
