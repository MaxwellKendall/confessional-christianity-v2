// The share image: the quote set like the entry page (Marcellus on the
// off-white card, Cinzel labels, the one ochre accent), its source, and the
// first proof text behind it. Two shapes — `f=og` (1200×630, what link
// previews unfurl) and `f=portrait` (1080×1350, for posting the image
// itself). Content never changes for a given URL, so responses cache hard.
import { readFile } from 'node:fs/promises';
import path from 'node:path';

import { ImageResponse } from 'next/og';
import type { NextRequest } from 'next/server';

import { parseSelection } from '@/lib/share';
import { excerpt, resolveShare, shareScripture } from '@/lib/shareContent';

const COLORS = {
  card: '#faf9f6',
  canvas: '#e9e6dd',
  ink: '#211e19',
  ink2: '#5c574c',
  ink3: '#8a8378',
  hairline: '#ddd8cd',
  ochre: '#ab7e2e',
};

const FORMATS = {
  og: { width: 1200, height: 630, pad: 64, scale: 1 },
  portrait: { width: 1080, height: 1350, pad: 88, scale: 1.25 },
} as const;
type Format = keyof typeof FORMATS;

const fontDir = path.join(process.cwd(), 'src/assets/fonts');
const fonts = Promise.all([
  readFile(path.join(fontDir, 'Marcellus-Regular.ttf')),
  readFile(path.join(fontDir, 'Cinzel-Regular.ttf')),
  readFile(path.join(fontDir, 'Cinzel-SemiBold.ttf')),
]);

/** Quote size by length, so a one-line answer fills the card and a long
 * article still fits it. */
const quoteSize = (chars: number, format: Format): number => {
  const steps = format === 'og'
    ? [[70, 54], [140, 44], [220, 36], [320, 30], [Infinity, 26]]
    : [[100, 74], [180, 62], [280, 52], [400, 44], [Infinity, 38]];
  return steps.find(([max]) => chars <= max)![1];
};

export async function GET(
  request: NextRequest,
  { params }: { params: Promise<{ confession: string; entry: string }> },
) {
  const { confession, entry } = await params;
  const search = request.nextUrl.searchParams;
  const format: Format = search.get('f') === 'portrait' ? 'portrait' : 'og';
  const share = await resolveShare(confession, entry, parseSelection(search));
  if (!share) return new Response('Not found', { status: 404 });

  const { width, height, pad, scale } = FORMATS[format];
  const { quote } = share;
  const [scripture] = await shareScripture(quote, 1);
  const moreRefs = quote.refs.length - (scripture ? 1 : 0);
  const quoteChars = quote.quote.length + (quote.question?.length ?? 0);
  const passageBudget = format === 'og' ? Math.max(0, 230 - quoteChars / 2) : Math.max(120, 420 - quoteChars / 2);
  const [marcellus, cinzel, cinzelSemi] = await fonts;

  return new ImageResponse(
    (
      <div
        style={{
          width, height, display: 'flex', padding: 18 * scale, background: COLORS.canvas,
        }}
      >
        <div
          style={{
            flex: 1,
            display: 'flex',
            flexDirection: 'column',
            background: COLORS.card,
            border: `1px solid ${COLORS.hairline}`,
            padding: `${pad * 0.8}px ${pad}px`,
            fontFamily: 'Marcellus',
            color: COLORS.ink,
          }}
        >
          <div
            style={{
              display: 'flex',
              fontFamily: 'Cinzel',
              fontSize: 17 * scale,
              letterSpacing: 3,
              textTransform: 'uppercase',
              color: COLORS.ochre,
            }}
          >
            {`${share.page.documentTitle} · ${share.label}`}
          </div>

          <div style={{ display: 'flex', flexDirection: 'column', flex: 1, justifyContent: 'center', gap: 18 * scale }}>
            {quote.question && (
              <div
                style={{
                  display: 'flex', fontFamily: 'Cinzel', fontWeight: 600, fontSize: 26 * scale, color: COLORS.ink2, lineHeight: 1.3,
                }}
              >
                {`Q. ${quote.question}`}
              </div>
            )}
            <div style={{ display: 'flex', fontSize: quoteSize(quoteChars, format), lineHeight: 1.32 }}>
              {quote.question ? `A. ${quote.quote}` : `“${quote.quote}”`}
            </div>
          </div>

          {scripture && (
            <div
              style={{
                display: 'flex',
                flexDirection: 'column',
                gap: 8 * scale,
                borderTop: `1px solid ${COLORS.hairline}`,
                paddingTop: 20 * scale,
                marginTop: 12 * scale,
              }}
            >
              {scripture.text && passageBudget > 60 && (
                <div style={{ display: 'flex', fontSize: 21 * scale, color: COLORS.ink2, lineHeight: 1.45 }}>
                  {`“${excerpt(scripture.text, passageBudget)}”`}
                </div>
              )}
              <div
                style={{
                  display: 'flex', fontFamily: 'Cinzel', fontSize: 15 * scale, letterSpacing: 2, textTransform: 'uppercase', color: COLORS.ink3,
                }}
              >
                {`${scripture.citation}${scripture.text ? ' (ESV)' : ''}${moreRefs > 0 ? ` · +${moreRefs} more proof text${moreRefs === 1 ? '' : 's'}` : ''}`}
              </div>
            </div>
          )}

          <div
            style={{
              display: 'flex',
              justifyContent: 'space-between',
              alignItems: 'center',
              marginTop: 22 * scale,
              fontFamily: 'Cinzel',
              fontSize: 15 * scale,
              letterSpacing: 3,
              textTransform: 'uppercase',
              color: COLORS.ink3,
            }}
          >
            <span style={{ fontWeight: 600, color: COLORS.ink }}>Confessional Christianity</span>
            <span>confessionalchristianity.com</span>
          </div>
        </div>
      </div>
    ),
    {
      width,
      height,
      fonts: [
        { name: 'Marcellus', data: marcellus, weight: 400, style: 'normal' },
        { name: 'Cinzel', data: cinzel, weight: 400, style: 'normal' },
        { name: 'Cinzel', data: cinzelSemi, weight: 600, style: 'normal' },
      ],
      headers: {
        'Cache-Control': 'public, max-age=86400, s-maxage=2592000, stale-while-revalidate=86400',
      },
    },
  );
}
