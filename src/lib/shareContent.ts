// Server-side resolution of a share URL into what its page and images show:
// the entry, the quote, where it comes from, and its Scripture.
import { loadConfessionContent } from './confessionContent';
import { entryPageLabel } from './entryDisplay';
import { fetchEsvPassage } from './esvServer';
import { getEntryPage, type EntryPage } from './library';
import { buildShareQuote, contextPath, sharePath, type ShareQuote, type ShareSelection } from './share';

export interface ResolvedShare {
  page: EntryPage;
  quote: ShareQuote;
  /** "Q. 1", "Chapter 1 · Article 2" — the entry page's own label. */
  label: string;
  /** "Westminster Shorter Catechism, Q. 1" — the attribution line. */
  source: string;
  path: string;
  context: string;
}

export const resolveShare = async (
  slug: string,
  segment: string,
  selection: ShareSelection,
): Promise<ResolvedShare | null> => {
  const page = await getEntryPage(slug, segment);
  if (!page) return null;
  // an unknown marker or empty range falls back to the whole entry, so a
  // link mangled in transit still shows something true
  const quote = buildShareQuote(page.item, selection) ?? buildShareQuote(page.item, { kind: 'entry' });
  if (!quote) return null;
  const content = await loadConfessionContent(slug);
  const label = entryPageLabel(page.item, content?.contentById);
  return {
    page,
    quote,
    label,
    source: `${page.documentTitle}, ${label}`,
    path: sharePath(slug, segment, quote.selection),
    context: contextPath(slug, segment, quote.selection),
  };
};

export interface SharedScripture {
  citation: string;
  osis: string;
  text: string | null;
}

/** ESV text for the first `limit` proof texts behind a quote — the share
 * page shows them all; images lead with the first. */
export const shareScripture = async (quote: ShareQuote, limit = quote.refs.length): Promise<SharedScripture[]> => (
  Promise.all(quote.refs.slice(0, limit).map(async (ref) => ({
    ...ref,
    text: await fetchEsvPassage(ref.osis),
  })))
);

/** Cuts a passage for an image at a word boundary near `max` characters. */
export const excerpt = (text: string, max: number): string => {
  if (text.length <= max) return text;
  const head = text.slice(0, max);
  const lastSpace = head.lastIndexOf(' ');
  return `${head.slice(0, lastSpace > 0 ? lastSpace : max).replace(/[\s,;:]+$/, '')}…`;
};
