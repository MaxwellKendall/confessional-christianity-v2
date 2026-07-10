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
  });

  const response = await fetch(`https://api.esv.org/v3/passage/text/?${params}`, {
    headers: { Authorization: `Token ${key}` },
    next: { revalidate: 60 * 60 * 24 * 30 },
  });

  if (!response.ok) {
    return NextResponse.json({ citation, text: null });
  }

  const data = (await response.json()) as { passages?: string[] };
  const text = data.passages?.[0]?.replace(/\s+/g, ' ').trim() ?? null;
  return NextResponse.json({ citation, text });
}
