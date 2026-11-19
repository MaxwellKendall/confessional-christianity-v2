import { NextRequest, NextResponse } from 'next/server';

import { parseOsisBibleReference } from '@/lib/bible';
import { anchorPassage, splitVerses, type VerseAnchor } from '@/lib/esvVerses';

interface EsvPassageResponse {
  passages?: string[];
  /** [start, end] BBCCCVVV ids, one pair per passage */
  parsed?: [number, number][];
}

// Fetches proof-text scripture for a session step. Server-side only: the ESV
// key never reaches the browser (unlike v1's NEXT_PUBLIC_ usage). Responses
// are cacheable — passages never change.
export async function GET(request: NextRequest) {
  const osis = request.nextUrl.searchParams.get('osis');
  if (!osis) {
    return NextResponse.json({ error: 'osis required' }, { status: 400 });
  }
  // Proof texts (ScriptureView) render as a single
  // flowing quote, so their whitespace is collapsed to one line below.
  // A full-chapter read (ReadingChapterView) wants the ESV API's own
  // paragraph breaks and poetry indentation intact instead.
  const formatted = request.nextUrl.searchParams.get('formatted') === 'true';
  // The verse-by-verse reader (TKL-872) needs to know where each verse
  // starts. verses=true: one entry per verse, whitespace collapsed.
  // formatted=true&anchors=true: the formatted text plus each verse's start
  // offset. Both ask the ESV for verse numbers and strip them out here.
  const verses = request.nextUrl.searchParams.get('verses') === 'true';
  const anchors = formatted && request.nextUrl.searchParams.get('anchors') === 'true';
  if (verses || anchors) {
    return versesResponse(osis, verses ? 'verses' : 'anchors');
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

type VersesMode = 'verses' | 'anchors';

const degraded = (citation: string, mode: VersesMode) =>
  NextResponse.json(mode === 'verses' ? { citation, verses: null } : { citation, text: null, anchors: null });

async function versesResponse(osis: string, mode: VersesMode) {
  const citation = parseOsisBibleReference(osis);
  const key = process.env.ESV_API_KEY;
  if (!key) {
    return degraded(citation, mode);
  }

  const params = new URLSearchParams({
    q: citation,
    'include-passage-references': 'false',
    'include-verse-numbers': 'true',
    'include-footnotes': 'false',
    'include-headings': 'false',
    'include-short-copyright': 'false',
    'line-length': '0',
  });

  const response = await fetch(`https://api.esv.org/v3/passage/text/?${params}`, {
    headers: { Authorization: `Token ${key}` },
    next: { revalidate: 60 * 60 * 24 * 30 },
  });

  if (!response.ok) {
    return degraded(citation, mode);
  }

  const data = (await response.json()) as EsvPassageResponse;
  const passages = data.passages ?? [];
  if (passages.length === 0 || !data.parsed || data.parsed.length !== passages.length) {
    return degraded(citation, mode);
  }

  // Same cleanup as the formatted=true path, so the anchored text matches it.
  let text = '';
  const allAnchors: VerseAnchor[] = [];
  passages.forEach((passage, i) => {
    const anchored = anchorPassage(passage.trim().replace(/\n{3,}/g, '\n\n'), data.parsed![i][0]);
    const base = text.length === 0 ? 0 : text.length + 2;
    text = text.length === 0 ? anchored.text : `${text}\n\n${anchored.text}`;
    allAnchors.push(...anchored.anchors.map((a) => ({ ...a, offset: a.offset + base })));
  });

  if (mode === 'verses') {
    return NextResponse.json({ citation, verses: splitVerses(text, allAnchors) });
  }
  return NextResponse.json({ citation, text, anchors: allAnchors });
}
