import { readFileSync } from 'fs';
import path from 'path';

import { describe, expect, test, vi } from 'vitest';

import { GENERATION_SCHEMA, SERMON_FIELDS, mergeSermons, validateSermon, type SermonDetails } from '@/lib/lordsDay/cards';
import { handleCardsRequest } from '@/lib/lordsDay/handler';
import { createRateLimiter } from '@/lib/lordsDay/rateLimit';
import { createPageReplayCache } from '@/lib/lordsDay/replayCache';
import { sermonFieldMadeUp, sermonFieldMatches, sermonFieldMisread } from '../evals/lords-day-cards/sermonMatch';

// TKL-1061: the cards call also reads which sermon this was (title, preacher,
// passage, church, date) from the notes. Every field is optional and null
// unless the notes say it; the server drops anything it can't find there.

const EMPTY: SermonDetails = { title: null, preacher: null, passage: null, church: null, serviceDate: null };

const SMYRNA = `Rev 2:8-11  To the Church at Smyrna  Grace Presbyterian
The hatred of the world is part of our heritage with Christ.`;

describe('validateSermon', () => {
  test('nothing from the model → every field null', () => {
    expect(validateSermon(undefined, SMYRNA)).toEqual(EMPTY);
    expect(validateSermon('To the Church at Smyrna', SMYRNA)).toEqual(EMPTY);
    expect(validateSermon([], SMYRNA)).toEqual(EMPTY);
    expect(validateSermon({}, SMYRNA)).toEqual(EMPTY);
  });

  test('keeps fields the notes contain, trimmed; the passage becomes a canonical reference', () => {
    const sermon = validateSermon(
      { title: '  To the Church at Smyrna ', passage: 'Revelation 2:8-11', church: 'Grace Presbyterian', preacher: null },
      SMYRNA,
    );
    expect(sermon).toEqual({
      title: 'To the Church at Smyrna',
      preacher: null,
      passage: 'Revelation 2:8-11',
      church: 'Grace Presbyterian',
      serviceDate: null,
    });
  });

  test('a title, preacher or church the notes never mention is dropped as invented', () => {
    const sermon = validateSermon(
      { title: 'Faithful unto Death', preacher: 'John Calvin', church: 'First Baptist', passage: 'Revelation 2:8-11' },
      SMYRNA,
    );
    expect(sermon.title).toBeNull();
    expect(sermon.preacher).toBeNull();
    expect(sermon.church).toBeNull();
    expect(sermon.passage).toBe('Revelation 2:8-11');
  });

  test('tolerates the model tidying a word or adding an honorific, but every real word must be in the notes', () => {
    const notes = 'MARK 4:33-41: An Fearful Circumstance 07/26/26\nRev Ross Hodges';
    const sermon = validateSermon({ title: 'A Fearful Circumstance', preacher: 'Rev. Ross Hodges' }, notes);
    expect(sermon.title).toBe('A Fearful Circumstance');
    expect(sermon.preacher).toBe('Rev. Ross Hodges');
    expect(validateSermon({ preacher: 'Ross Hodgson' }, notes).preacher).toBeNull();
  });

  test('a compound passage keeps its first reference', () => {
    expect(validateSermon({ passage: 'Matthew 5:9; 43-48' }, 'MATTHEW 5:9; 43-48').passage).toBe('Matthew 5:9');
  });

  test('a passage that is not a real reference is null', () => {
    expect(validateSermon({ passage: 'Hezekiah 3:1' }, SMYRNA).passage).toBeNull();
    expect(validateSermon({ passage: 'Revelation 40:1' }, SMYRNA).passage).toBeNull();
    expect(validateSermon({ passage: 42 }, SMYRNA).passage).toBeNull();
  });

  test('the service date must be a real YYYY-MM-DD date', () => {
    const page = 'Mark 4  07/26/26  1 30';
    expect(validateSermon({ serviceDate: '2026-07-26' }, page).serviceDate).toBe('2026-07-26');
    expect(validateSermon({ serviceDate: '2026-02-30' }, page).serviceDate).toBeNull();
    expect(validateSermon({ serviceDate: 'July 26' }, page).serviceDate).toBeNull();
    expect(validateSermon({ serviceDate: '1850-01-01' }, page).serviceDate).toBeNull();
  });

  test('a date or passage whose numbers are not on the page is invented', () => {
    const page = 'Mark 4:33-41 07/26/26';
    expect(validateSermon({ serviceDate: '2026-11-22' }, page).serviceDate).toBeNull();
    expect(validateSermon({ serviceDate: '2020-07-26' }, page).serviceDate).toBeNull();
    expect(validateSermon({ passage: 'Mark 5:1-20' }, page).passage).toBeNull();
    expect(validateSermon({ passage: 'Mark 4:33-41' }, page).passage).toBe('Mark 4:33-41');
  });

  test('over-long strings are not titles', () => {
    const long = 'word '.repeat(60);
    expect(validateSermon({ title: long }, long).title).toBeNull();
  });
});

describe('mergeSermons', () => {
  test('first non-null value per field, in page order', () => {
    const merged = mergeSermons([
      { ...EMPTY, passage: 'Revelation 2:8-11' },
      { ...EMPTY, passage: 'John 15:18', title: 'To the Church at Smyrna' },
      EMPTY,
    ]);
    expect(merged).toEqual({ ...EMPTY, passage: 'Revelation 2:8-11', title: 'To the Church at Smyrna' });
    expect(mergeSermons([])).toEqual(EMPTY);
  });
});

describe('the Gemini schema', () => {
  test('adds an optional sermon object with the five fields, leaving the card contract as it was', () => {
    const sermon = (GENERATION_SCHEMA.properties as Record<string, { properties?: Record<string, unknown> }>).sermon;
    expect(Object.keys(sermon.properties ?? {}).sort()).toEqual([...SERMON_FIELDS].sort());
    expect(GENERATION_SCHEMA.required).toEqual(['extractedText', 'cards']);
  });
});

const geminiFetch = (reply: (body: Record<string, unknown>) => unknown) =>
  vi.fn(async (_url: string, init: RequestInit) => {
    const body = JSON.parse(init.body as string);
    return new Response(
      JSON.stringify({
        candidates: [{ content: { parts: [{ text: JSON.stringify(reply(body)) }] }, finishReason: 'STOP' }],
        usageMetadata: { promptTokenCount: 10, candidatesTokenCount: 10 },
      }),
      { status: 200 },
    );
  });

const run = async (body: unknown, fetchImpl: ReturnType<typeof geminiFetch>, replayCache = createPageReplayCache()) => {
  const response = await handleCardsRequest(
    new Request('http://localhost/api/lords-day/cards', {
      method: 'POST',
      headers: { authorization: 'Bearer t', 'content-type': 'application/json' },
      body: JSON.stringify(body),
    }),
    {
      geminiApiKey: 'k',
      model: 'gemini-3.8-flash',
      verifyAccessToken: async () => ({ sub: 'user-1' }),
      limiter: createRateLimiter({ limit: 100, windowMs: 60_000 }),
      replayCache,
      fetchImpl: fetchImpl as unknown as typeof fetch,
      retryDelayMs: 0,
    },
  );
  return (await response.text())
    .split('\n')
    .filter(Boolean)
    .map((line) => JSON.parse(line));
};

describe('the cards stream', () => {
  const pages = (body: Record<string, unknown>) => {
    const data = (body.contents as { parts: { inlineData?: { data: string } }[] }[])[0].parts[0].inlineData?.data;
    return data === 'cGFnZTE='
      ? {
          extractedText: SMYRNA,
          sermon: { title: 'To the Church at Smyrna', passage: 'Revelation 2:8-11', preacher: 'Invented Name' },
          cards: [{ kind: 'key_point', text: 'The world hated Christ first.' }],
        }
      : {
          extractedText: 'Rev 2:10 Do not fear. Be faithful unto death. Grace Presbyterian',
          sermon: { passage: 'Revelation 2:10', church: 'Grace Presbyterian' },
          cards: [{ kind: 'verse', reference: 'Revelation 2:10' }],
        };
  };
  const twoPages = {
    images: [
      { data: 'cGFnZTE=', mimeType: 'image/jpeg' },
      { data: 'cGFnZTI=', mimeType: 'image/jpeg' },
    ],
  };

  test('each page sends its sermon details right after the page event; done carries them merged in page order', async () => {
    const events = await run(twoPages, geminiFetch(pages));
    const sermonEvents = events.filter((e) => e.type === 'sermon');
    expect(sermonEvents).toEqual(
      expect.arrayContaining([
        {
          type: 'sermon',
          page: 0,
          sermon: { title: 'To the Church at Smyrna', preacher: null, passage: 'Revelation 2:8-11', church: null, serviceDate: null },
        },
        {
          type: 'sermon',
          page: 1,
          sermon: { title: null, preacher: null, passage: 'Revelation 2:10', church: 'Grace Presbyterian', serviceDate: null },
        },
      ]),
    );
    for (const s of sermonEvents) {
      const pageIndex = events.findIndex((e) => e.type === 'page' && e.page === s.page);
      expect(events.indexOf(s)).toBe(pageIndex + 1);
    }
    const done = events.find((e) => e.type === 'done');
    expect(done.sermon).toEqual({
      title: 'To the Church at Smyrna',
      preacher: null,
      passage: 'Revelation 2:8-11',
      church: 'Grace Presbyterian',
      serviceDate: null,
    });
  });

  test('a page whose notes name nothing sends no sermon event, and done has every field null', async () => {
    const events = await run(
      { extractedText: 'God is good.' },
      geminiFetch(() => ({ extractedText: '', cards: [{ kind: 'key_point', text: 'God is good.' }] })),
    );
    expect(events.filter((e) => e.type === 'sermon')).toEqual([]);
    expect(events.find((e) => e.type === 'done').sermon).toEqual(EMPTY);
  });

  test('typed notes are checked against the typed text', async () => {
    const events = await run(
      { extractedText: 'Psalm 23. The Lord is my shepherd.' },
      geminiFetch(() => ({ extractedText: '', sermon: { passage: 'Psalm 23', title: 'The Good Shepherd' }, cards: [] })),
    );
    expect(events.find((e) => e.type === 'done').sermon).toEqual({ ...EMPTY, passage: 'Psalms 23' });
  });

  test('a replayed page brings back the same sermon details without calling the model', async () => {
    const cache = createPageReplayCache();
    const fetchImpl = geminiFetch(pages);
    await run(twoPages, fetchImpl, cache);
    const replayed = await run(twoPages, fetchImpl, cache);
    expect(fetchImpl).toHaveBeenCalledTimes(2);
    expect(replayed.find((e) => e.type === 'done').sermon.title).toBe('To the Church at Smyrna');
  });
});

// The eval set's sermon truth (evals/lords-day-cards/truth.json, `sermon` per case)
// is checked offline here: a reply that repeats the truth passes through whole, and
// a reply that makes up every field the truth leaves null comes back null.
describe('sermon eval truth', () => {
  const truth = JSON.parse(readFileSync(path.join(__dirname, '..', 'evals', 'lords-day-cards', 'truth.json'), 'utf8')) as {
    cases: { id: string; typed?: string; sermon?: Record<string, string | null> }[];
  };
  const sermonCases = truth.cases.filter((c) => c.sermon);

  test('covers the Rev 2:8-11 note, a title-and-preacher heading, a passage only, and nothing at all', () => {
    const ids = sermonCases.map((c) => c.id);
    expect(ids).toEqual(expect.arrayContaining(['smyrna-rev-2', 'sermon-12', 'passage-only', 'no-heading']));
    const none = sermonCases.find((c) => c.id === 'no-heading')!.sermon!;
    expect(Object.values(none).every((v) => v === null)).toBe(true);
    const only = sermonCases.find((c) => c.id === 'passage-only')!.sermon!;
    expect(SERMON_FIELDS.filter((f) => only[f] !== null)).toEqual(['passage']);
  });

  test.each(sermonCases.filter((c) => c.typed).map((c) => [c.id, c] as const))(
    '%s: invented fields are dropped, real ones kept',
    (_id, c) => {
      const source = c.typed!;
      const made = validateSermon(
        { title: 'Faithful unto Death', preacher: 'Charles Spurgeon', church: 'Westminster Chapel', passage: 'Jude 1:3', serviceDate: '2026-01-04' },
        source,
      );
      for (const field of ['title', 'preacher', 'church'] as const) {
        if (c.sermon![field] === null) expect(made[field]).toBeNull();
      }
      const faithful = validateSermon(c.sermon, source);
      for (const field of SERMON_FIELDS) expect(sermonFieldMatches(field, faithful[field], c.sermon![field])).toBe(true);
    },
  );
});

describe('the eval tells a misreading from an invention', () => {
  test('a misread digit or tidied word is a misread; a different name, passage or a value where there is none is made up', () => {
    expect(sermonFieldMisread('serviceDate', '2020-07-26', '2026-07-26')).toBe(true);
    expect(sermonFieldMadeUp('serviceDate', '2020-07-26', '2026-07-26')).toBe(false);
    expect(sermonFieldMisread('passage', 'Mark 4:35-41', 'Mark 4:33-41')).toBe(true);
    expect(sermonFieldMadeUp('passage', 'Mark 5:1-20', 'Mark 4:33-41')).toBe(true);
    expect(sermonFieldMatches('title', 'An Fearful Circumstance', 'fearful circumstance')).toBe(true);
    expect(sermonFieldMadeUp('preacher', 'John Calvin', 'ross hodges')).toBe(true);
    expect(sermonFieldMadeUp('title', 'Faithful unto Death', null)).toBe(true);
    expect(sermonFieldMadeUp('title', null, 'church at smyrna')).toBe(false);
  });
});
