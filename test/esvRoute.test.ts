import { readFileSync } from 'fs';
import path from 'path';
import { NextRequest } from 'next/server';
import { afterEach, beforeEach, describe, expect, test, vi } from 'vitest';

import { GET } from '@/app/api/esv/route';

// Recorded ESV API responses (api.esv.org/v3/passage/text), one per request
// shape. `numbered` = include-verse-numbers=true + line-length=0 (what the
// verses and anchors modes send), `formatted` = today's formatted=true
// request, `default` = today's default request. No live network in tests.
const fixture = (name: string): unknown =>
  JSON.parse(readFileSync(path.join(__dirname, 'fixtures', 'esv', `${name}.json`), 'utf8'));

const passageOf = (name: string): string => (fixture(name) as { passages: string[] }).passages[0];

let requested: URL[] = [];

const serve = (body: unknown, init: { ok?: boolean } = {}) => {
  vi.stubGlobal(
    'fetch',
    vi.fn(async (url: string) => {
      requested.push(new URL(url));
      return { ok: init.ok ?? true, json: async () => body } as Response;
    }),
  );
};

const get = async (query: string) => {
  const response = await GET(new NextRequest(`http://localhost/api/esv?${query}`));
  return { status: response.status, body: await response.json() };
};

beforeEach(() => {
  requested = [];
  process.env.ESV_API_KEY = 'test-key';
});

afterEach(() => {
  vi.unstubAllGlobals();
  delete process.env.ESV_API_KEY;
});

describe('verses=true', () => {
  test('splits a range into one entry per verse, in order, with clean text', async () => {
    serve(fixture('romans-8-28-30.numbered'));
    const { body } = await get('osis=Rom.8.28-Rom.8.30&verses=true');

    expect(Object.keys(body).sort()).toEqual(['citation', 'verses']);
    expect(body.citation).toBe('Romans 8:28-30');
    expect(body.verses.map((v: { osis: string }) => v.osis)).toEqual(['Rom.8.28', 'Rom.8.29', 'Rom.8.30']);
    expect(body.verses.map((v: { verse: number }) => v.verse)).toEqual([28, 29, 30]);
    expect(body.verses[0].text).toBe(
      'And we know that for those who love God all things work together for good, for those who are called according to his purpose.',
    );
    for (const { text } of body.verses) {
      expect(text).not.toMatch(/\[\d+\]/);
      expect(text).not.toMatch(/\s{2,}|\n/);
      expect(text).toBe(text.trim());
    }
  });

  test('asks the ESV API for verse numbers, without footnotes or headings', async () => {
    serve(fixture('romans-8-28-30.numbered'));
    await get('osis=Rom.8.28-Rom.8.30&verses=true');

    expect(requested).toHaveLength(1);
    const params = requested[0].searchParams;
    expect(params.get('q')).toBe('Romans 8:28-30');
    expect(params.get('include-verse-numbers')).toBe('true');
    expect(params.get('include-footnotes')).toBe('false');
    expect(params.get('include-headings')).toBe('false');
    expect(params.get('include-passage-references')).toBe('false');
    expect(params.get('include-short-copyright')).toBe('false');
  });

  test('a cross-chapter range gets the right chapter in each osis id', async () => {
    serve(fixture('romans-8-38-9-1.numbered'));
    const { body } = await get('osis=Rom.8.38-Rom.9.1&verses=true');

    expect(body.verses.map((v: { osis: string }) => v.osis)).toEqual(['Rom.8.38', 'Rom.8.39', 'Rom.9.1']);
    expect(body.verses[2].text).toBe(
      'I am speaking the truth in Christ—I am not lying; my conscience bears me witness in the Holy Spirit—',
    );
  });

  test('a single verse yields one entry', async () => {
    serve(fixture('romans-8-28.numbered'));
    const { body } = await get('osis=Rom.8.28&verses=true');

    expect(body.verses).toHaveLength(1);
    expect(body.verses[0].osis).toBe('Rom.8.28');
  });

  test('a psalm keeps poetry lines as one verse and drops the superscription', async () => {
    serve(fixture('psalm-23.numbered'));
    const { body } = await get('osis=Ps.23&verses=true');

    expect(body.verses.map((v: { osis: string }) => v.osis)).toEqual([
      'Ps.23.1',
      'Ps.23.2',
      'Ps.23.3',
      'Ps.23.4',
      'Ps.23.5',
      'Ps.23.6',
    ]);
    expect(body.verses[0].text).toBe('The LORD is my shepherd; I shall not want.');
    expect(body.verses[2].text).toBe(
      'He restores my soul. He leads me in paths of righteousness for his name’s sake.',
    );
  });

  test('a cross-chapter psalm range does not glue the next superscription onto the last verse', async () => {
    serve(fixture('psalm-22-31-23-1.numbered'));
    const { body } = await get('osis=Ps.22.31-Ps.23.1&verses=true');

    expect(body.verses.map((v: { osis: string }) => v.osis)).toEqual(['Ps.22.31', 'Ps.23.1']);
    expect(body.verses[0].text).toBe(
      'they shall come and proclaim his righteousness to a people yet unborn, that he has done it.',
    );
  });

  test('degrades to verses: null without a key', async () => {
    delete process.env.ESV_API_KEY;
    serve(fixture('romans-8-28-30.numbered'));
    const { body } = await get('osis=Rom.8.28-Rom.8.30&verses=true');

    expect(body).toEqual({ citation: 'Romans 8:28-30', verses: null });
    expect(requested).toHaveLength(0);
  });

  test('degrades to verses: null when the ESV API fails', async () => {
    serve({}, { ok: false });
    const { body } = await get('osis=Rom.8.28-Rom.8.30&verses=true');

    expect(body).toEqual({ citation: 'Romans 8:28-30', verses: null });
  });
});

describe('formatted=true&anchors=true', () => {
  test('returns the same text as formatted=true plus an anchor per verse', async () => {
    serve(fixture('psalm-23.formatted'));
    const plain = (await get('osis=Ps.23&formatted=true')).body;
    serve(fixture('psalm-23.numbered'));
    const { body } = await get('osis=Ps.23&formatted=true&anchors=true');

    expect(Object.keys(body).sort()).toEqual(['anchors', 'citation', 'text']);
    expect(body.text).toBe(plain.text);
    expect(body.text).toContain('\n        I will fear no evil,');
    expect(body.text).not.toMatch(/\[\d+\]/);
    expect(body.anchors.map((a: { osis: string }) => a.osis)).toEqual([
      'Ps.23.1',
      'Ps.23.2',
      'Ps.23.3',
      'Ps.23.4',
      'Ps.23.5',
      'Ps.23.6',
    ]);
    expect(body.text.slice(body.anchors[0].offset)).toMatch(/^The LORD is my shepherd/);
    expect(body.text.slice(body.anchors[1].offset)).toMatch(/^ {4}He makes me lie down/);
    expect(body.text.slice(body.anchors[5].offset)).toMatch(/^Surely goodness and mercy/);
  });

  test('anchors a cross-chapter prose range at each verse start', async () => {
    serve(fixture('romans-8-38-9-1.numbered'));
    const { body } = await get('osis=Rom.8.38-Rom.9.1&formatted=true&anchors=true');

    expect(body.text).toContain('\n\n');
    const starts = body.anchors.map((a: { offset: number }) => body.text.slice(a.offset, a.offset + 12));
    expect(body.anchors.map((a: { osis: string }) => a.osis)).toEqual(['Rom.8.38', 'Rom.8.39', 'Rom.9.1']);
    expect(starts).toEqual(['For I am sur', 'nor height n', 'I am speakin']);
  });

  test('requests line-length=0 so the client can reflow', async () => {
    serve(fixture('psalm-23.numbered'));
    await get('osis=Ps.23&formatted=true&anchors=true');

    expect(requested[0].searchParams.get('line-length')).toBe('0');
    expect(requested[0].searchParams.get('include-verse-numbers')).toBe('true');
  });

  test('degrades to text: null and anchors: null', async () => {
    serve({}, { ok: false });
    expect((await get('osis=Ps.23&formatted=true&anchors=true')).body).toEqual({
      citation: 'Psalms 23',
      text: null,
      anchors: null,
    });
    delete process.env.ESV_API_KEY;
    expect((await get('osis=Ps.23&formatted=true&anchors=true')).body).toEqual({
      citation: 'Psalms 23',
      text: null,
      anchors: null,
    });
  });
});

// Byte-for-byte regression guard for the two existing response shapes: the
// expected bodies are what the route produced before verses/anchors existed.
describe('existing responses are unchanged', () => {
  const BASE_PARAMS = {
    'include-passage-references': 'false',
    'include-verse-numbers': 'false',
    'include-footnotes': 'false',
    'include-headings': 'false',
    'include-short-copyright': 'false',
  };

  test('default response', async () => {
    serve(fixture('romans-8-28-30.default'));
    const response = await GET(new NextRequest('http://localhost/api/esv?osis=Rom.8.28-Rom.8.30'));
    const raw = await response.text();

    expect(Object.fromEntries(requested[0].searchParams)).toEqual({ q: 'Romans 8:28-30', ...BASE_PARAMS });
    expect(raw).toBe(
      JSON.stringify({
        citation: 'Romans 8:28-30',
        text: passageOf('romans-8-28-30.default').trim().replace(/\s+/g, ' '),
      }),
    );
  });

  test('formatted=true response', async () => {
    serve(fixture('psalm-23.formatted'));
    const response = await GET(new NextRequest('http://localhost/api/esv?osis=Ps.23&formatted=true'));
    const raw = await response.text();

    expect(Object.fromEntries(requested[0].searchParams)).toEqual({
      q: 'Psalms 23',
      ...BASE_PARAMS,
      'line-length': '0',
    });
    expect(raw).toBe(
      JSON.stringify({
        citation: 'Psalms 23',
        text: passageOf('psalm-23.formatted').trim().replace(/\n{3,}/g, '\n\n'),
      }),
    );
  });

  test('anchors=true without formatted=true is the default response', async () => {
    serve(fixture('romans-8-28-30.default'));
    const { body } = await get('osis=Rom.8.28-Rom.8.30&anchors=true');

    expect(Object.keys(body).sort()).toEqual(['citation', 'text']);
    expect(requested[0].searchParams.get('include-verse-numbers')).toBe('false');
  });

  test('missing key and non-ok still degrade to text: null', async () => {
    serve({}, { ok: false });
    expect((await get('osis=Ps.23')).body).toEqual({ citation: 'Psalms 23', text: null });
    delete process.env.ESV_API_KEY;
    expect((await get('osis=Ps.23&formatted=true')).body).toEqual({ citation: 'Psalms 23', text: null });
  });

  test('the key is sent only as a header, never in the URL or the body', async () => {
    serve(fixture('romans-8-28-30.numbered'));
    const { body } = await get('osis=Rom.8.28-Rom.8.30&verses=true');
    const fetchMock = vi.mocked(fetch);

    expect(requested[0].toString()).not.toContain('test-key');
    expect(JSON.stringify(body)).not.toContain('test-key');
    expect(fetchMock.mock.calls[0][1]).toMatchObject({ headers: { Authorization: 'Token test-key' } });
  });
});
