import { NextRequest, NextResponse } from 'next/server';

import { parseOsisBibleReference } from '@/lib/bible';
import { fetchEsvPassage } from '@/lib/esvServer';

// Fetches proof-text scripture for a session step. Server-side only: the ESV
// key never reaches the browser (unlike v1's NEXT_PUBLIC_ usage). Responses
// are cacheable — passages never change.
export async function GET(request: NextRequest) {
  const osis = request.nextUrl.searchParams.get('osis');
  if (!osis) {
    return NextResponse.json({ error: 'osis required' }, { status: 400 });
  }
  // Proof texts (ScriptureView, DevotionWorshipView) render as a single
  // flowing quote, so their whitespace is collapsed to one line. A
  // full-chapter read (ReadingChapterView) wants the ESV API's own
  // paragraph breaks and poetry indentation intact instead.
  const formatted = request.nextUrl.searchParams.get('formatted') === 'true';

  const citation = parseOsisBibleReference(osis);
  // null text degrades to citation-only rendering (no key, or no passage)
  const text = await fetchEsvPassage(osis, { formatted });
  return NextResponse.json({ citation, text });
}
