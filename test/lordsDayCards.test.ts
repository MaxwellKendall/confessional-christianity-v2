import { afterEach, describe, expect, test, vi } from 'vitest';

import { CARD_KINDS, GENERATION_SCHEMA, normalizeForMatch, validateGeneratedCards } from '@/lib/lordsDay/cards';
import {
  CardsError,
  GEMINI_CARDS_INPUT_PER_1M,
  GEMINI_CARDS_MODEL_DEFAULT,
  GEMINI_CARDS_OUTPUT_PER_1M,
  cardsModel,
  draftPage,
  geminiCost,
} from '@/lib/lordsDay/gemini';

const SOURCE = `Matthew 5:9. "Blessed are the peacemakers, for they shall be called sons of God."
We have eternal, internal peace w/ God. The gospel is a message of peace.`;

const validate = (cards: unknown[], preacher?: string) =>
  validateGeneratedCards(cards, { sourceText: SOURCE, preacher, page: 0 });

describe('validateGeneratedCards', () => {
  test('keeps exactly the three kinds, in order, with page-scoped ids', () => {
    const { cards, rejected } = validate([
      { kind: 'key_point', text: 'The gospel is the foundation of peace.' },
      { kind: 'quote', text: 'The gospel is a message of peace.' },
      { kind: 'verse', reference: 'Matthew 5:9' },
    ]);
    expect(rejected).toEqual([]);
    expect(cards.map((c) => c.kind)).toEqual(['key_point', 'quote', 'verse']);
    expect(cards.map((c) => c.id)).toEqual(['p0-0', 'p0-1', 'p0-2']);
    expect(cards.map((c) => c.order)).toEqual([0, 1, 2]);
    expect(CARD_KINDS).toEqual(['key_point', 'quote', 'verse']);
  });

  test('a malformed response: unknown kinds, non-objects and empty text are rejected, never passed through', () => {
    const { cards, rejected } = validate([
      { kind: 'reflection_question', text: 'How will you make peace this week?' },
      { kind: 'prayer', text: 'Lord, make us peacemakers.' },
      { kind: 'KEY_POINT', text: 'Case games are not a kind.' },
      'just a string',
      null,
      { text: 'no kind at all' },
      { kind: 'key_point', text: '   ' },
      { kind: 'key_point', text: 'x'.repeat(281) },
      { kind: 'key_point', text: 'Peace with God comes first.' },
    ]);
    expect(cards).toHaveLength(1);
    expect(cards[0]).toMatchObject({ kind: 'key_point', text: 'Peace with God comes first.' });
    expect(rejected.map((r) => r.reason)).toEqual([
      'unknown_kind',
      'unknown_kind',
      'unknown_kind',
      'not_object',
      'not_object',
      'unknown_kind',
      'empty_text',
      'text_too_long',
    ]);
  });

  test('a quote must be a span of the extracted text (normalised), so a composed quote is rejected', () => {
    const { cards, rejected } = validate([
      // case, curly quotes, punctuation and line breaks differ from the source: still a match
      { kind: 'quote', text: '“blessed are the PEACEMAKERS — for they shall be called sons of God”' },
      { kind: 'quote', text: 'Peace is the evidence of a heart at rest in Christ.' },
    ]);
    expect(cards).toHaveLength(1);
    expect(cards[0].text).toBe('blessed are the PEACEMAKERS — for they shall be called sons of God');
    expect(rejected).toEqual([{ index: 1, reason: 'quote_not_in_source' }]);
  });

  test('a one-word quote is not a quote', () => {
    const { rejected } = validate([{ kind: 'quote', text: 'peace' }]);
    expect(rejected).toEqual([{ index: 0, reason: 'quote_too_short' }]);
  });

  test('attribution comes only from the request: absent preacher means absent attribution', () => {
    const quote = { kind: 'quote', text: 'The gospel is a message of peace.', attribution: 'Rev. Invented' };
    expect(validate([quote]).cards[0].attribution).toBeUndefined();
    expect(validate([quote], '  Rev. Ross Hodges ').cards[0].attribution).toBe('Rev. Ross Hodges');
    // key points carry no attribution even when a preacher is known
    expect(validate([{ kind: 'key_point', text: 'Peace first.' }], 'Rev. Ross Hodges').cards[0].attribution).toBeUndefined();
  });

  test('a verse card returns only a reference (canonical, plus OSIS), never Scripture text', () => {
    const { cards } = validate([
      { kind: 'verse', reference: 'Psalm 86:5', text: 'For you, O Lord, are good and forgiving...' },
      { kind: 'verse', reference: 'Matthew 5:43-48' },
      { kind: 'verse', reference: 'Malachi 1' },
    ]);
    expect(cards).toEqual([
      { id: 'p0-0', kind: 'verse', page: 0, order: 0, reference: 'Psalms 86:5', osis: 'Ps.86.5' },
      { id: 'p0-1', kind: 'verse', page: 0, order: 1, reference: 'Matthew 5:43-48', osis: 'Matt.5.43-Matt.5.48' },
      { id: 'p0-2', kind: 'verse', page: 0, order: 2, reference: 'Malachi 1', osis: 'Mal.1' },
    ]);
    for (const card of cards) expect(card).not.toHaveProperty('text');
  });

  test('a verse card whose reference is not a real reference is rejected', () => {
    const { cards, rejected } = validate([
      { kind: 'verse', reference: 'Blessed are the peacemakers, for they shall be called sons of God' },
      { kind: 'verse', reference: 'Hezekiah 3:1' },
      { kind: 'verse', reference: 'Psalm 151:1' },
      { kind: 'verse' },
    ]);
    expect(cards).toEqual([]);
    expect(rejected.map((r) => r.reason)).toEqual([
      'bad_reference',
      'bad_reference',
      'bad_reference',
      'bad_reference',
    ]);
  });

  test('caps the cards kept per page', () => {
    const many = Array.from({ length: 20 }, (_, i) => ({ kind: 'key_point', text: `Point ${i}` }));
    expect(validate(many).cards).toHaveLength(12);
  });

  test('normalizeForMatch folds case, quotes, punctuation and whitespace', () => {
    expect(normalizeForMatch('  “Love is the\nfountain,” (John Owen) ')).toBe('love is the fountain john owen');
  });
});

describe('the Gemini schema', () => {
  test('pins the card kinds to exactly the three, at the API', () => {
    const kind = GENERATION_SCHEMA.properties.cards.items.properties.kind;
    expect(kind.enum).toEqual(['key_point', 'quote', 'verse']);
    expect(GENERATION_SCHEMA.required).toEqual(['extractedText', 'cards']);
  });
});

describe('cost', () => {
  test('rates for the default model are recorded beside it (standard rates from 2027-01-01, errs high)', () => {
    expect(GEMINI_CARDS_MODEL_DEFAULT).toBe('gemini-3.8-flash');
    expect(GEMINI_CARDS_INPUT_PER_1M).toBe(1.5);
    expect(GEMINI_CARDS_OUTPUT_PER_1M).toBe(7.5);
  });

  test('thinking tokens bill as output', () => {
    const cost = geminiCost({ promptTokenCount: 1_000_000, candidatesTokenCount: 500_000, thoughtsTokenCount: 500_000 });
    expect(cost).toBeCloseTo(1.5 + 7.5, 6);
    expect(geminiCost(undefined)).toBe(0);
  });
});

describe('cardsModel', () => {
  afterEach(() => {
    delete process.env.GEMINI_CARDS_MODEL;
  });
  test('defaults to gemini-3.8-flash and is overridden by GEMINI_CARDS_MODEL', () => {
    expect(cardsModel()).toBe('gemini-3.8-flash');
    process.env.GEMINI_CARDS_MODEL = 'gemini-3.5-flash-lite';
    expect(cardsModel()).toBe('gemini-3.5-flash-lite');
  });
});

const geminiReply = (payload: unknown, usage = { promptTokenCount: 1000, candidatesTokenCount: 200, thoughtsTokenCount: 100 }) =>
  new Response(
    JSON.stringify({
      candidates: [{ content: { parts: [{ text: JSON.stringify(payload) }] }, finishReason: 'STOP' }],
      usageMetadata: usage,
    }),
    { status: 200, headers: { 'content-type': 'application/json' } },
  );

describe('draftPage', () => {
  const image = { kind: 'image' as const, data: 'aGVsbG8=', mimeType: 'image/jpeg' };
  const opts = (fetchImpl: typeof fetch) => ({ apiKey: 'k', model: 'gemini-3.8-flash', fetchImpl, retryDelayMs: 0 });

  test('asks Gemini for JSON constrained by the card schema, with the image inline and the key in a header', async () => {
    const fetchImpl = vi.fn(async () => geminiReply({ extractedText: 'notes', cards: [] }));
    const result = await draftPage(image, { passage: 'Matthew 5:9' }, opts(fetchImpl as unknown as typeof fetch));

    expect(fetchImpl).toHaveBeenCalledTimes(1);
    const [url, init] = fetchImpl.mock.calls[0] as unknown as [string, RequestInit];
    expect(url).toBe('https://generativelanguage.googleapis.com/v1beta/models/gemini-3.8-flash:generateContent');
    expect(url).not.toContain('key=');
    expect((init.headers as Record<string, string>)['x-goog-api-key']).toBe('k');
    const body = JSON.parse(init.body as string);
    expect(body.generationConfig.responseMimeType).toBe('application/json');
    expect(body.generationConfig.responseJsonSchema).toEqual(GENERATION_SCHEMA);
    expect(body.contents[0].parts[0]).toEqual({ inlineData: { mimeType: 'image/jpeg', data: 'aGVsbG8=' } });
    expect(body.contents[0].parts[1].text).toContain('Matthew 5:9');
    expect(result.extractedText).toBe('notes');
    expect(result.costUsd).toBeCloseTo((1000 * 1.5 + 300 * 7.5) / 1_000_000, 9);
  });

  test('typed notes: the source text is the typed text, not whatever the model echoes', async () => {
    const fetchImpl = vi.fn(async () => geminiReply({ extractedText: 'something else', cards: [] }));
    const result = await draftPage({ kind: 'text', text: 'My typed notes' }, {}, opts(fetchImpl as unknown as typeof fetch));
    expect(result.extractedText).toBe('My typed notes');
    const body = JSON.parse((fetchImpl.mock.calls[0] as unknown as [string, RequestInit])[1].body as string);
    expect(body.contents[0].parts).toHaveLength(1);
    expect(body.contents[0].parts[0].text).toContain('My typed notes');
  });

  test('retries a dropped connection, then succeeds', async () => {
    const fetchImpl = vi
      .fn()
      .mockRejectedValueOnce(new TypeError('fetch failed'))
      .mockResolvedValueOnce(geminiReply({ extractedText: 'ok', cards: [] }));
    const result = await draftPage(image, {}, opts(fetchImpl as unknown as typeof fetch));
    expect(fetchImpl).toHaveBeenCalledTimes(2);
    expect(result.extractedText).toBe('ok');
  });

  test('retries a 503 once, then succeeds', async () => {
    const fetchImpl = vi
      .fn()
      .mockResolvedValueOnce(new Response('busy', { status: 503 }))
      .mockResolvedValueOnce(geminiReply({ extractedText: 'ok', cards: [] }));
    await draftPage(image, {}, opts(fetchImpl as unknown as typeof fetch));
    expect(fetchImpl).toHaveBeenCalledTimes(2);
  });

  test('a connection that keeps failing becomes a typed 502, never a raw throw', async () => {
    const fetchImpl = vi.fn().mockRejectedValue(new TypeError('fetch failed'));
    const error = await draftPage(image, {}, opts(fetchImpl as unknown as typeof fetch)).catch((e) => e);
    expect(error).toBeInstanceOf(CardsError);
    expect(error).toMatchObject({ status: 502, code: 'provider_unreachable' });
    expect(fetchImpl).toHaveBeenCalledTimes(3);
  });

  test('a provider error status becomes a typed 502', async () => {
    const fetchImpl = vi.fn(async () => new Response('{"error":{"message":"bad"}}', { status: 400 }));
    const error = await draftPage(image, {}, opts(fetchImpl as unknown as typeof fetch)).catch((e) => e);
    expect(error).toMatchObject({ status: 502, code: 'provider_error' });
    expect(fetchImpl).toHaveBeenCalledTimes(1);
  });

  test('output that is not the schema (bad JSON, missing cards) becomes a typed 502', async () => {
    for (const text of ['not json', '{"extractedText":"x"}', '[]']) {
      const fetchImpl = vi.fn(
        async () =>
          new Response(JSON.stringify({ candidates: [{ content: { parts: [{ text }] } }] }), { status: 200 }),
      );
      const error = await draftPage(image, {}, opts(fetchImpl as unknown as typeof fetch)).catch((e) => e);
      expect(error).toMatchObject({ status: 502, code: 'bad_model_output' });
    }
  });

  test('a safety-blocked reply becomes a typed 422', async () => {
    const fetchImpl = vi.fn(
      async () => new Response(JSON.stringify({ candidates: [{ finishReason: 'SAFETY' }] }), { status: 200 }),
    );
    const error = await draftPage(image, {}, opts(fetchImpl as unknown as typeof fetch)).catch((e) => e);
    expect(error).toMatchObject({ status: 422, code: 'blocked' });
  });
});
