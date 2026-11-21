import { generateKeyPairSync } from 'crypto';
import { afterEach, beforeEach, describe, expect, test, vi } from 'vitest';

import { createCognitoVerifier } from '@/lib/lordsDay/auth';
import { handleCardsRequest, type CardsDeps } from '@/lib/lordsDay/handler';
import { createRateLimiter } from '@/lib/lordsDay/rateLimit';
import { POST } from '@/app/api/lords-day/cards/route';

import { createTestPool, TEST_CLIENT_ID, TEST_POOL_ID, type TestPool } from './support/cognitoJwt';

const GEMINI_HOST = 'generativelanguage.googleapis.com';

let pool: TestPool;
let geminiCalls: { url: string; body: Record<string, unknown> }[];

// One fake Gemini: page text depends on which image (or typed text) was sent.
const fakeGemini = (replyFor: (body: Record<string, unknown>) => unknown, delayFor?: (body: Record<string, unknown>) => number) =>
  vi.fn(async (url: string, init: RequestInit) => {
    const body = JSON.parse(init.body as string);
    geminiCalls.push({ url, body });
    if (delayFor) await new Promise((r) => setTimeout(r, delayFor(body)));
    return new Response(
      JSON.stringify({
        candidates: [{ content: { parts: [{ text: JSON.stringify(replyFor(body)) }] }, finishReason: 'STOP' }],
        usageMetadata: { promptTokenCount: 2000, candidatesTokenCount: 300, thoughtsTokenCount: 200 },
      }),
      { status: 200 },
    );
  });

const imageData = (body: Record<string, unknown>) =>
  (body.contents as { parts: { inlineData?: { data: string } }[] }[])[0].parts[0].inlineData?.data;

const pageReply = (body: Record<string, unknown>) => {
  const data = imageData(body);
  if (data === 'cGFnZTE=') {
    return {
      extractedText: 'Page one. "God is ready to forgive." Ps 86:5',
      cards: [
        { kind: 'key_point', text: 'We are called to bring peace.' },
        { kind: 'quote', text: 'God is ready to forgive.' },
        { kind: 'verse', reference: 'Psalm 86:5' },
      ],
    };
  }
  return {
    extractedText: 'Page two. Strife does not come from the gospel.',
    cards: [
      { kind: 'reflection_question', text: 'Where is there strife?' },
      { kind: 'quote', text: 'A sentence the preacher never said.' },
      { kind: 'key_point', text: 'Strife does not come from the gospel.' },
    ],
  };
};

const deps = (overrides: Partial<CardsDeps> = {}): CardsDeps => {
  const verifier = createCognitoVerifier({ userPoolId: TEST_POOL_ID, clientId: TEST_CLIENT_ID });
  verifier.cacheJwks(pool.jwks as never);
  return {
    geminiApiKey: 'test-gemini-key',
    model: 'gemini-3.8-flash',
    verifyAccessToken: async (token) => {
      const payload = await verifier.verify(token);
      return { sub: String(payload.sub) };
    },
    limiter: createRateLimiter({ limit: 20, windowMs: 60 * 60 * 1000 }),
    fetchImpl: fakeGemini(pageReply) as unknown as typeof fetch,
    retryDelayMs: 0,
    ...overrides,
  };
};

const request = (body: unknown, token: string | null = pool.sign(), headers: Record<string, string> = {}) =>
  new Request('http://localhost/api/lords-day/cards', {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      ...(token ? { authorization: `Bearer ${token}` } : {}),
      ...headers,
    },
    body: typeof body === 'string' ? body : JSON.stringify(body),
  });

const twoPages = {
  images: [
    { data: 'cGFnZTE=', mimeType: 'image/jpeg' },
    { data: 'cGFnZTI=', mimeType: 'image/jpeg' },
  ],
  passage: 'Matthew 5:9',
  title: 'Peacemakers',
};

const readEvents = async (response: Response) => {
  const text = await response.text();
  return text
    .split('\n')
    .filter(Boolean)
    .map((line) => JSON.parse(line));
};

beforeEach(() => {
  pool = createTestPool();
  geminiCalls = [];
});

afterEach(() => {
  vi.unstubAllGlobals();
  delete process.env.GEMINI_API_KEY;
  delete process.env.COGNITO_USER_POOL_ID;
  delete process.env.COGNITO_CLIENT_ID;
});

describe('configuration', () => {
  test('the route reads the Gemini key from the environment at runtime: missing key → clear 503, no provider call', async () => {
    process.env.COGNITO_USER_POOL_ID = TEST_POOL_ID;
    process.env.COGNITO_CLIENT_ID = TEST_CLIENT_ID;
    const fetchSpy = vi.fn();
    vi.stubGlobal('fetch', fetchSpy);
    const response = await POST(request(twoPages));
    expect(response.status).toBe(503);
    expect(await response.json()).toEqual({ error: 'generator_not_configured' });
    expect(fetchSpy).not.toHaveBeenCalled();
  });

  test('missing Cognito pool or client config → 503, not a crash', async () => {
    process.env.GEMINI_API_KEY = 'set';
    const response = await POST(request(twoPages));
    expect(response.status).toBe(503);
    expect(await response.json()).toEqual({ error: 'auth_not_configured' });
  });

  test('handler with no key → 503', async () => {
    const response = await handleCardsRequest(request(twoPages), deps({ geminiApiKey: undefined }));
    expect(response.status).toBe(503);
  });
});

describe('authentication', () => {
  const expectUnauthorized = async (response: Response) => {
    expect(response.status).toBe(401);
    expect(await response.json()).toEqual({ error: 'unauthorized' });
    expect(geminiCalls).toHaveLength(0);
  };

  test('no token → 401', async () => {
    await expectUnauthorized(await handleCardsRequest(request(twoPages, null), deps()));
  });

  test('a garbage token → 401', async () => {
    await expectUnauthorized(await handleCardsRequest(request(twoPages, 'not.a.jwt'), deps()));
  });

  test('an expired token → 401', async () => {
    const past = Math.floor(Date.now() / 1000) - 7200;
    await expectUnauthorized(await handleCardsRequest(request(twoPages, pool.sign({ iat: past, exp: past + 60 })), deps()));
  });

  test('a token for another app client → 401', async () => {
    await expectUnauthorized(await handleCardsRequest(request(twoPages, pool.sign({ client_id: 'someone-else' })), deps()));
  });

  test('a token from another pool → 401', async () => {
    const other = 'https://cognito-idp.us-east-1.amazonaws.com/us-east-1_OtherPool';
    await expectUnauthorized(await handleCardsRequest(request(twoPages, pool.sign({ iss: other })), deps()));
  });

  test('an id token instead of an access token → 401', async () => {
    await expectUnauthorized(await handleCardsRequest(request(twoPages, pool.sign({ token_use: 'id' })), deps()));
  });

  test('a token signed by a different key → 401', async () => {
    const { privateKey } = generateKeyPairSync('rsa', { modulusLength: 2048 });
    await expectUnauthorized(await handleCardsRequest(request(twoPages, pool.sign({}, privateKey)), deps()));
  });
});

describe('rate limit', () => {
  test('limits on the verified subject, not the client', async () => {
    const d = deps({ limiter: createRateLimiter({ limit: 2, windowMs: 60_000 }) });
    const textBody = { extractedText: 'Page one. "God is ready to forgive."' };
    for (let i = 0; i < 2; i += 1) {
      expect((await handleCardsRequest(request(textBody, pool.sign({ sub: 'alice' })), d)).status).toBe(200);
    }
    const limited = await handleCardsRequest(request(textBody, pool.sign({ sub: 'alice' })), d);
    expect(limited.status).toBe(429);
    expect(Number(limited.headers.get('retry-after'))).toBeGreaterThan(0);
    expect(await limited.json()).toEqual({ error: 'rate_limited' });
    // another person is unaffected
    expect((await handleCardsRequest(request(textBody, pool.sign({ sub: 'bob' })), d)).status).toBe(200);
  });

  test('the limiter window rolls over', () => {
    let now = 0;
    const limiter = createRateLimiter({ limit: 1, windowMs: 1000, now: () => now });
    expect(limiter.take('a').ok).toBe(true);
    expect(limiter.take('a')).toEqual({ ok: false, retryAfterSeconds: 1 });
    now = 1000;
    expect(limiter.take('a').ok).toBe(true);
  });
});

describe('request validation', () => {
  const cases: [string, unknown, number, string][] = [
    ['not JSON', '{', 400, 'invalid_json'],
    ['neither images nor text', { passage: 'Matthew 5:9' }, 400, 'images_or_text_required'],
    ['both images and text', { ...twoPages, extractedText: 'x' }, 400, 'images_or_text_required'],
    ['empty images', { images: [] }, 400, 'images_or_text_required'],
    ['too many pages', { images: Array.from({ length: 7 }, () => twoPages.images[0]) }, 400, 'too_many_images'],
    ['an unsupported image type', { images: [{ data: 'cGFnZTE=', mimeType: 'application/pdf' }] }, 400, 'bad_image'],
    ['image data that is not base64', { images: [{ data: 'not base64!', mimeType: 'image/jpeg' }] }, 400, 'bad_image'],
    ['typed text that is too long', { extractedText: 'x'.repeat(20_001) }, 400, 'text_too_long'],
    ['a passage that is not a string', { extractedText: 'x', passage: 5 }, 400, 'bad_metadata'],
  ];
  test.each(cases)('%s → %i %s', async (_name, body, status, error) => {
    const response = await handleCardsRequest(request(body), deps());
    expect(response.status).toBe(status);
    expect(await response.json()).toEqual({ error });
    expect(geminiCalls).toHaveLength(0);
  });

  test('a body over the size limit → 413 before parsing', async () => {
    const response = await handleCardsRequest(request(twoPages, pool.sign(), { 'content-length': '5000000' }), deps());
    expect(response.status).toBe(413);
  });
});

describe('the stream', () => {
  test('streams NDJSON: started, then each page and its cards as the page finishes, then done with the ordered list', async () => {
    // page 0 finishes after page 1, so events arrive out of page order
    const fetchImpl = fakeGemini(pageReply, (body) => (imageData(body) === 'cGFnZTE=' ? 30 : 0));
    const response = await handleCardsRequest(
      request({ ...twoPages, preacher: 'Rev. Ross Hodges' }),
      deps({ fetchImpl: fetchImpl as unknown as typeof fetch }),
    );
    expect(response.status).toBe(200);
    expect(response.headers.get('content-type')).toContain('application/x-ndjson');
    expect(response.headers.get('cache-control')).toBe('no-store');

    const events = await readEvents(response);
    expect(events[0]).toEqual({ type: 'started', pages: 2, model: 'gemini-3.8-flash' });
    expect(events.map((e) => e.type)).toEqual(['started', 'page', 'card', 'page', 'card', 'card', 'card', 'done']);
    // page 1 (the fast one) arrives first
    expect(events[1]).toEqual({ type: 'page', page: 1, extractedText: 'Page two. Strife does not come from the gospel.', rejected: 2 });

    const done = events.at(-1);
    expect(done.cards.map((c: { id: string }) => c.id)).toEqual(['p0-0', 'p0-1', 'p0-2', 'p1-0']);
    expect(done.cards.map((c: { kind: string }) => c.kind)).toEqual(['key_point', 'quote', 'verse', 'key_point']);
    expect(done.cards[1]).toEqual({
      id: 'p0-1',
      kind: 'quote',
      page: 0,
      order: 1,
      text: 'God is ready to forgive.',
      attribution: 'Rev. Ross Hodges',
    });
    expect(done.cards[2]).toEqual({ id: 'p0-2', kind: 'verse', page: 0, order: 2, reference: 'Psalms 86:5', osis: 'Ps.86.5' });
    expect(done.rejected).toBe(2);
    expect(done.failedPages).toEqual([]);
    expect(done.costUsd).toBeCloseTo(2 * ((2000 * 1.5 + 500 * 7.5) / 1_000_000), 9);

    // every streamed card event is one of the three kinds
    for (const e of events.filter((x) => x.type === 'card')) {
      expect(['key_point', 'quote', 'verse']).toContain(e.card.kind);
    }
    // one call per page, both to Gemini
    expect(geminiCalls).toHaveLength(2);
    expect(geminiCalls.every((c) => new URL(c.url).host === GEMINI_HOST)).toBe(true);
    // the preacher's name is never sent to the model (it can't be put in anyone's mouth)
    expect(JSON.stringify(geminiCalls.map((c) => c.body))).not.toContain('Ross Hodges');
  });

  test('typed notes go through one call; quotes are checked against the typed text', async () => {
    const fetchImpl = fakeGemini(() => ({
      extractedText: '',
      cards: [
        { kind: 'quote', text: 'peace with God' },
        { kind: 'quote', text: 'not in the notes at all' },
      ],
    }));
    const response = await handleCardsRequest(
      request({ extractedText: 'We have eternal, internal peace with God.' }),
      deps({ fetchImpl: fetchImpl as unknown as typeof fetch }),
    );
    const events = await readEvents(response);
    const done = events.at(-1);
    expect(done.cards).toHaveLength(1);
    expect(done.cards[0]).toMatchObject({ kind: 'quote', text: 'peace with God' });
    expect(done.cards[0]).not.toHaveProperty('attribution');
    expect(geminiCalls).toHaveLength(1);
  });

  test('one failed page is reported in the stream and the other pages still arrive', async () => {
    const fetchImpl = vi.fn(async (url: string, init: RequestInit) => {
      const body = JSON.parse(init.body as string);
      if (imageData(body) === 'cGFnZTI=') return new Response('nope', { status: 400 });
      return fakeGemini(pageReply)(url, init);
    });
    const response = await handleCardsRequest(request(twoPages), deps({ fetchImpl: fetchImpl as unknown as typeof fetch }));
    const events = await readEvents(response);
    expect(events).toContainEqual({ type: 'error', page: 1, code: 'provider_error', message: expect.any(String) });
    const done = events.at(-1);
    expect(done.failedPages).toEqual([1]);
    expect(done.cards).toHaveLength(3);
  });

  test('persists nothing: the only outbound call is to Gemini', async () => {
    const fetchImpl = fakeGemini(pageReply);
    const spy = vi.fn();
    vi.stubGlobal('fetch', spy);
    await readEvents(await handleCardsRequest(request(twoPages), deps({ fetchImpl: fetchImpl as unknown as typeof fetch })));
    expect(spy).not.toHaveBeenCalled();
    expect(fetchImpl).toHaveBeenCalledTimes(2);
  });
});
