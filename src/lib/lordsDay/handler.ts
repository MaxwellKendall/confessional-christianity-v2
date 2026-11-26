import { randomUUID } from 'crypto';

import { bearerToken } from './auth';
import { validateGeneratedCards, type DraftCard } from './cards';
import { CardsError, draftPage, type PageInput } from './gemini';
import type { RateLimiter } from './rateLimit';
import { pageReplayKey, type CachedPage, type CachedPageCard, type PageReplayCache } from './replayCache';

// POST /api/lords-day/cards: sermon notes (photos or typed text) → drafted
// Key point / Quote / Verse cards. Returns drafts only: nothing is persisted
// here (notes and cards sync through the account, TKL-905 / TKL-866).
//
// Request (JSON, ≤ 4 MB; resize photos on the phone to ~1600 px first):
//   { images?: [{ data: <base64>, mimeType: "image/jpeg" | ... }]  (1–6 pages)
//     extractedText?: string  (the "Type instead" path; exactly one of the two)
//     passage?, title?, preacher?: string
//     replayOnlyPages?: number[]  (request page indices that must only replay, never regenerate)
//     expectedGenerationIds?: Record<string, string> }
// Header: Authorization: Bearer <Cognito access token>.
//
// Errors before generation are JSON with a status (400, 401, 413, 429, 503).
// Otherwise a 200 NDJSON stream, one event per line, so the app fills cards in
// as each page finishes instead of waiting on a spinner:
//   { type: "started", pages, model }
//   { type: "page", page, extractedText, rejected, cardCount, generationId }  then  { type: "card", card } per card
//   { type: "error", page, code, message }            (that page failed; others continue)
//   { type: "done", cards: [...ordered by page, order], rejected, failedPages, costUsd }

export interface CardsDeps {
  geminiApiKey?: string;
  model: string;
  /** null: Cognito isn't configured on this deployment */
  verifyAccessToken: ((token: string) => Promise<{ sub: string }>) | null;
  limiter: RateLimiter;
  replayCache?: PageReplayCache;
  fetchImpl?: typeof fetch;
  retryDelayMs?: number;
}

export const MAX_BODY_BYTES = 4_000_000;
export const MAX_PAGES = 6;
export const MAX_TYPED_CHARS = 20_000;
const MAX_META_CHARS = 200;
const IMAGE_TYPES = new Set(['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif']);
const BASE64 = /^[A-Za-z0-9+/]+={0,2}$/;

const json = (status: number, body: Record<string, unknown>, headers: Record<string, string> = {}) =>
  new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json', 'cache-control': 'no-store', ...headers } });

const fail = (status: number, error: string) => json(status, { error });

interface ParsedRequest {
  pages: PageInput[];
  passage?: string;
  title?: string;
  preacher?: string;
  replayOnlyPages: Set<number>;
  expectedGenerationIds: Map<number, string>;
}

const parseReplayControls = (
  rawReplayOnly: unknown,
  rawExpectedIds: unknown,
  pageCount: number,
): { replayOnlyPages: Set<number>; expectedGenerationIds: Map<number, string> } | Response => {
  const replayOnlyPages = new Set<number>();
  if (rawReplayOnly !== undefined && rawReplayOnly !== null) {
    if (!Array.isArray(rawReplayOnly)) return fail(400, 'bad_replay_pages');
    for (const item of rawReplayOnly) {
      if (typeof item !== 'number' || !Number.isInteger(item) || item < 0 || item >= pageCount) {
        return fail(400, 'bad_replay_pages');
      }
      replayOnlyPages.add(item);
    }
  }

  const expectedGenerationIds = new Map<number, string>();
  if (rawExpectedIds !== undefined && rawExpectedIds !== null) {
    if (typeof rawExpectedIds !== 'object' || Array.isArray(rawExpectedIds)) return fail(400, 'bad_replay_pages');
    for (const [k, v] of Object.entries(rawExpectedIds as Record<string, unknown>)) {
      if (!/^\d+$/.test(k)) return fail(400, 'bad_replay_pages');
      const idx = Number(k);
      if (!Number.isInteger(idx) || idx < 0 || idx >= pageCount) return fail(400, 'bad_replay_pages');
      if (typeof v !== 'string') return fail(400, 'bad_replay_pages');
      const trimmed = v.trim();
      if (!trimmed || trimmed.length > MAX_META_CHARS) return fail(400, 'bad_replay_pages');
      expectedGenerationIds.set(idx, trimmed);
    }
  }

  return { replayOnlyPages, expectedGenerationIds };
};

const parseBody = (body: unknown): ParsedRequest | Response => {
  if (!body || typeof body !== 'object' || Array.isArray(body)) return fail(400, 'invalid_json');
  const { images, extractedText, passage, title, preacher, replayOnlyPages, expectedGenerationIds } = body as Record<
    string,
    unknown
  >;

  const meta: Record<string, string | undefined> = {};
  for (const [name, value] of Object.entries({ passage, title, preacher })) {
    if (value === undefined || value === null) continue;
    if (typeof value !== 'string' || value.length > MAX_META_CHARS) return fail(400, 'bad_metadata');
    meta[name] = value.trim() || undefined;
  }

  const hasImages = Array.isArray(images) && images.length > 0;
  const hasText = typeof extractedText === 'string' && extractedText.trim().length > 0;
  if (hasImages === hasText) return fail(400, 'images_or_text_required');

  if (hasText) {
    if ((extractedText as string).length > MAX_TYPED_CHARS) return fail(400, 'text_too_long');
    const replay = parseReplayControls(replayOnlyPages, expectedGenerationIds, 1);
    if (replay instanceof Response) return replay;
    return { pages: [{ kind: 'text', text: extractedText as string }], ...meta, ...replay };
  }

  const list = images as unknown[];
  if (list.length > MAX_PAGES) return fail(400, 'too_many_images');
  const pages: PageInput[] = [];
  for (const image of list) {
    const { data, mimeType } = (image && typeof image === 'object' ? image : {}) as Record<string, unknown>;
    if (typeof mimeType !== 'string' || !IMAGE_TYPES.has(mimeType)) return fail(400, 'bad_image');
    if (typeof data !== 'string' || !BASE64.test(data)) return fail(400, 'bad_image');
    pages.push({ kind: 'image', data, mimeType });
  }
  const replay = parseReplayControls(replayOnlyPages, expectedGenerationIds, pages.length);
  if (replay instanceof Response) return replay;
  return { pages, ...meta, ...replay };
};

export const handleCardsRequest = async (request: Request, deps: CardsDeps): Promise<Response> => {
  if (!deps.geminiApiKey) return fail(503, 'generator_not_configured');
  if (!deps.verifyAccessToken) return fail(503, 'auth_not_configured');

  const token = bearerToken(request);
  if (!token) return fail(401, 'unauthorized');
  let sub: string;
  try {
    ({ sub } = await deps.verifyAccessToken(token));
  } catch {
    return fail(401, 'unauthorized');
  }

  const limit = deps.limiter.take(sub);
  if (!limit.ok) return json(429, { error: 'rate_limited' }, { 'retry-after': String(limit.retryAfterSeconds) });

  if (Number(request.headers.get('content-length') ?? 0) > MAX_BODY_BYTES) return fail(413, 'too_large');
  let raw: string;
  try {
    raw = await request.text();
  } catch {
    return fail(400, 'invalid_json');
  }
  if (raw.length > MAX_BODY_BYTES) return fail(413, 'too_large');
  let body: unknown;
  try {
    body = JSON.parse(raw);
  } catch {
    return fail(400, 'invalid_json');
  }
  const parsed = parseBody(body);
  if (parsed instanceof Response) return parsed;

  const { pages, passage, title, preacher, replayOnlyPages, expectedGenerationIds } = parsed;
  const { geminiApiKey, model, replayCache, fetchImpl, retryDelayMs } = deps;
  const encoder = new TextEncoder();

  const stream = new ReadableStream<Uint8Array>({
    async start(controller) {
      const send = (event: Record<string, unknown>) => controller.enqueue(encoder.encode(`${JSON.stringify(event)}\n`));
      send({ type: 'started', pages: pages.length, model });

      const all: DraftCard[] = [];
      const failedPages: number[] = [];
      let rejected = 0;
      let costUsd = 0;

      await Promise.all(
        pages.map(async (input, page) => {
          try {
            const key = pageReplayKey({ sub, model, input, passage, title, preacher });
            const mustReplay = replayOnlyPages.has(page);
            const expectedGenId = expectedGenerationIds.get(page);

            const generatePage = async (): Promise<{ page: CachedPage; costUsd: number }> => {
              // the preacher is never sent: attribution is metadata, not model output
              const result = await draftPage(input, { passage, title }, { apiKey: geminiApiKey, model, fetchImpl, retryDelayMs });
              const { cards: validated, rejected: pageRejected } = validateGeneratedCards(result.rawCards, {
                sourceText: result.extractedText,
                preacher,
                page,
              });
              const generationId = randomUUID();
              const cachedCards: CachedPageCard[] = validated.map((card) => ({
                sourceKey: `${generationId}:${card.order}`,
                kind: card.kind,
                order: card.order,
                ...(card.text !== undefined ? { text: card.text } : {}),
                ...(card.reference !== undefined ? { reference: card.reference } : {}),
                ...(card.osis !== undefined ? { osis: card.osis } : {}),
                ...(card.attribution !== undefined ? { attribution: card.attribution } : {}),
              }));
              return {
                page: {
                  generationId,
                  extractedText: result.extractedText,
                  rejected: pageRejected.length,
                  cards: cachedCards,
                },
                costUsd: result.costUsd,
              };
            };

            let resolved: { page: CachedPage; costUsd: number; hit: boolean };
            if (mustReplay || expectedGenId !== undefined) {
              const cached = replayCache ? await replayCache.get(key) : null;
              if (!cached || (expectedGenId !== undefined && cached.generationId !== expectedGenId)) {
                failedPages.push(page);
                send({
                  type: 'error',
                  page,
                  code: 'replay_unavailable',
                  message: 'The original draft for this page is no longer available to resume.',
                });
                return;
              }
              resolved = { page: cached, costUsd: 0, hit: true };
            } else {
              resolved = replayCache
                ? await replayCache.getOrCreate(key, generatePage)
                : { ...(await generatePage()), hit: false };
            }

            costUsd += resolved.costUsd;
            rejected += resolved.page.rejected;
            const cards: DraftCard[] = resolved.page.cards.map((card) => ({
              id: `p${page}-${card.order}`,
              page,
              ...card,
            }));
            all.push(...cards);
            send({
              type: 'page',
              page,
              extractedText: resolved.page.extractedText,
              rejected: resolved.page.rejected,
              cardCount: cards.length,
              generationId: resolved.page.generationId,
            });
            for (const card of cards) send({ type: 'card', card });
          } catch (error) {
            failedPages.push(page);
            const known = error instanceof CardsError;
            if (!known) console.error('[lords-day/cards] unexpected page failure', error);
            send({
              type: 'error',
              page,
              code: known ? error.code : 'internal',
              message: known ? error.message : 'Something went wrong drafting this page.',
            });
          }
        }),
      );

      all.sort((a, b) => a.page - b.page || a.order - b.order);
      failedPages.sort((a, b) => a - b);
      // counts and cost only: never the notes or the cards
      console.info(
        `[lords-day/cards] model=${model} pages=${pages.length} failed=${failedPages.length} cards=${all.length} rejected=${rejected} costUsd=${costUsd.toFixed(5)}`,
      );
      send({ type: 'done', cards: all, rejected, failedPages, costUsd });
      controller.close();
    },
  });

  return new Response(stream, {
    status: 200,
    headers: {
      'content-type': 'application/x-ndjson; charset=utf-8',
      'cache-control': 'no-store',
      'x-accel-buffering': 'no',
    },
  });
};
