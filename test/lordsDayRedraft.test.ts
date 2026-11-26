import { describe, expect, test, vi } from 'vitest';

import { handleRedraftRequest, type RedraftDeps } from '@/lib/lordsDay/redraft';
import { createRateLimiter } from '@/lib/lordsDay/rateLimit';

const SOURCE = 'He is not finished with us. God works all things for good. Romans 8:28.';

const geminiReturning = (cards: unknown[]) =>
  vi.fn(async () =>
    new Response(
      JSON.stringify({
        candidates: [{ content: { parts: [{ text: JSON.stringify({ extractedText: SOURCE, cards }) }] }, finishReason: 'STOP' }],
        usageMetadata: { promptTokenCount: 500, candidatesTokenCount: 60 },
      }),
      { status: 200 },
    ),
  );

const deps = (over: Partial<RedraftDeps> = {}): RedraftDeps => ({
  geminiApiKey: 'k',
  model: 'gemini-test',
  verifyAccessToken: async () => ({ sub: 'user-1' }),
  limiter: createRateLimiter({ limit: 20, windowMs: 60_000 }),
  fetchImpl: geminiReturning([{ kind: 'key_point', text: 'God works all things for good.' }]),
  ...over,
});

const post = (body: unknown, token = 'tok') =>
  new Request('https://example.test/api/lords-day/cards/redraft', {
    method: 'POST',
    headers: { 'content-type': 'application/json', authorization: `Bearer ${token}` },
    body: JSON.stringify(body),
  });

describe('handleRedraftRequest', () => {
  test('returns one validated card drafted from the text already transcribed', async () => {
    const response = await handleRedraftRequest(post({ extractedText: SOURCE }), deps());
    expect(response.status).toBe(200);
    const { card } = await response.json();
    expect(card).toMatchObject({ kind: 'key_point', text: 'God works all things for good.' });
  });

  test('pins the kind when one is asked for, so a verse redrafts to a verse', async () => {
    const fetchImpl = geminiReturning([
      { kind: 'key_point', text: 'God works all things for good.' },
      { kind: 'verse', reference: 'Romans 8:28' },
    ]);
    const response = await handleRedraftRequest(post({ extractedText: SOURCE, kind: 'verse' }), deps({ fetchImpl }));
    const { card } = await response.json();
    expect(card.kind).toBe('verse');
    expect(card.reference).toBe('Romans 8:28');
    expect(card.osis).toBe('Rom.8.28');
  });

  test('never hands back the card being replaced', async () => {
    const fetchImpl = geminiReturning([
      { kind: 'key_point', text: 'God works all things for good.' },
      { kind: 'key_point', text: 'He is not finished with us.' },
    ]);
    const response = await handleRedraftRequest(
      post({ extractedText: SOURCE, kind: 'key_point', avoid: ['God works all things for good.'] }),
      deps({ fetchImpl }),
    );
    const { card } = await response.json();
    expect(card.text).toBe('He is not finished with us.');
  });

  test('a redraft with nothing usable is 422, so the caller keeps the original card', async () => {
    const fetchImpl = geminiReturning([{ kind: 'quote', text: 'A line that is not in the notes at all.' }]);
    const response = await handleRedraftRequest(post({ extractedText: SOURCE }), deps({ fetchImpl }));
    expect(response.status).toBe(422);
    expect(await response.json()).toEqual({ error: 'no_card' });
  });

  test('refuses without a token, and when Cognito is not configured', async () => {
    const noToken = new Request('https://example.test/api/lords-day/cards/redraft', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ extractedText: SOURCE }),
    });
    expect((await handleRedraftRequest(noToken, deps())).status).toBe(401);
    expect((await handleRedraftRequest(post({ extractedText: SOURCE }), deps({ verifyAccessToken: null }))).status).toBe(503);
  });

  test('shares the account rate limit, so repeated taps cannot run up a bill', async () => {
    const limiter = createRateLimiter({ limit: 1, windowMs: 60_000 });
    const d = deps({ limiter });
    expect((await handleRedraftRequest(post({ extractedText: SOURCE }), d)).status).toBe(200);
    expect((await handleRedraftRequest(post({ extractedText: SOURCE }), d)).status).toBe(429);
  });
});
