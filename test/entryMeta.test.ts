// TKL-681: every library entry page gets a unique, search-intent-matched meta
// title and description ("Westminster Shorter Catechism Question 1 — What Is
// the Chief End of Man?"), derived from the stored entry and its document.
import { describe, expect, it } from 'vitest';

import { loadConfessionContent } from '@/lib/confessionContent';
import { entryMetaDescription, entryMetaTitle, titleCase } from '@/lib/entryMeta';
import { getAllEntryParams, getEntryPage } from '@/lib/library';

const metaFor = async (confession: string, entry: string) => {
  const page = await getEntryPage(confession, entry);
  const content = await loadConfessionContent(confession);
  if (!page || !content) throw new Error(`no entry ${confession}/${entry}`);
  return {
    title: entryMetaTitle(page.documentTitle, page.item, content.contentById),
    description: entryMetaDescription(page.documentTitle, page.item, content.contentById),
  };
};

describe('titleCase', () => {
  it('capitalizes major words, keeps minor words lower and acronyms intact', () => {
    expect(titleCase('what is the chief end of man?')).toBe('What Is the Chief End of Man?');
    expect(titleCase('Of the going down of Christ into Hell.')).toBe('Of the Going Down of Christ into Hell.');
    expect(titleCase("of the LORD's day")).toBe("Of the LORD's Day");
  });
});

describe('entry meta titles', () => {
  it('catechism questions lead with document, question number and the question', async () => {
    const { title } = await metaFor('westminster-shorter-catechism', '1');
    expect(title).toBe('Westminster Shorter Catechism Question 1 — What Is the Chief End of Man?');
  });

  it('Heidelberg questions number by question, not Lord\'s Day', async () => {
    const { title } = await metaFor('heidelberg-catechism', '1-1');
    expect(title).toBe('Heidelberg Catechism Question 1 — What Is Thy Only Comfort in Life and Death?');
  });

  it('confession articles name chapter, article and the chapter subject', async () => {
    const { title } = await metaFor('westminster-confession-of-faith', '1-2');
    expect(title).toBe('Westminster Confession of Faith Chapter 1, Article 2 — Of the Holy Scripture');
  });

  it('Canons of Dort rejections name their chapter', async () => {
    const { title } = await metaFor('canons-of-dort', '1-rejections-2');
    expect(title).toBe('Canons of Dort Chapter 1, Rejection 2 — Of Divine Predestination');
  });

  it('chapter-level entries carry their subject without a trailing period', async () => {
    const { title } = await metaFor('thirty-nine-articles-of-religion', '3');
    expect(title).toBe('Thirty-Nine Articles Chapter 3 — Of the Going Down of Christ into Hell');
  });

  it('untitled entries fall back to document and label', async () => {
    const { title } = await metaFor('martin-luthers-95-theses', '1');
    expect(title).toBe('Luther’s Ninety-Five Theses — Thesis 1');
  });
});

describe('entry meta descriptions', () => {
  it('Q&A descriptions name the question and give the answer without footnote markers', async () => {
    const { description } = await metaFor('westminster-shorter-catechism', '1');
    expect(description).toBe(
      'Westminster Shorter Catechism Q. 1 answer: Man\'s chief end is to glorify God, and to enjoy him for ever.',
    );
  });

  it('article descriptions name where the text sits and quote its opening', async () => {
    const { description } = await metaFor('westminster-confession-of-faith', '1-2');
    expect(description.startsWith('Westminster Confession of Faith 1.2: Under the name of holy Scripture')).toBe(true);
    expect(description.length).toBeLessThanOrEqual(161);
  });
});

describe('every entry page', () => {
  it('has a unique title and a unique description of at most 160 characters', async () => {
    const params = await getAllEntryParams();
    expect(params.length).toBeGreaterThan(500);
    const titles = new Map<string, string>();
    const descriptions = new Map<string, string>();
    for (const { confession, entry } of params) {
      const key = `${confession}/${entry}`;
      const { title, description } = await metaFor(confession, entry);
      expect(title, key).not.toMatch(/\[[a-z0-9]+\]/i);
      expect(description, key).not.toMatch(/\[[a-z0-9]+\]/i);
      expect(description.length, key).toBeLessThanOrEqual(161);
      expect(titles.get(title), `${key} title duplicates`).toBeUndefined();
      expect(descriptions.get(description), `${key} description duplicates`).toBeUndefined();
      titles.set(title, key);
      descriptions.set(description, key);
    }
  });
});
