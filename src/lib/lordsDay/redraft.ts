import { bearerToken } from './auth';
import { CARD_KINDS, validateGeneratedCards, type CardKind, type DraftCard } from './cards';
import { CardsError, draftPage } from './gemini';
import type { RateLimiter } from './rateLimit';

// POST /api/lords-day/cards/redraft: one card, drafted again from the page text
// the model already transcribed (TKL-1053). No photo is re-read and no other
// card is touched, so a reader who dislikes one card can ask for another.
//
// Request (JSON): { extractedText, kind?, avoid?: string[], passage?, title?, preacher? }
//   kind  — pin the replacement to the same kind as the card being replaced.
//   avoid — text or references already on screen, so the model's answer is new.
// Header: Authorization: Bearer <Cognito access token>.
//
// 200 { card }, or 422 { error: "no_card" } when nothing valid came back — the
// caller keeps the card it already has. Shares the drafting rate limit.

export interface RedraftDeps {
  geminiApiKey?: string;
  model: string;
  /** null: Cognito isn't configured on this deployment */
  verifyAccessToken: ((token: string) => Promise<{ sub: string }>) | null;
  limiter: RateLimiter;
  fetchImpl?: typeof fetch;
  retryDelayMs?: number;
}

const MAX_TEXT_CHARS = 20_000;
const MAX_META_CHARS = 200;
const MAX_AVOID = 32;

const json = (status: number, body: Record<string, unknown>) =>
  new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json', 'cache-control': 'no-store' } });

const fail = (status: number, error: string) => json(status, { error });

const meta = (value: unknown): string | undefined => {
  if (typeof value !== 'string') return undefined;
  const trimmed = value.trim();
  return trimmed && trimmed.length <= MAX_META_CHARS ? trimmed : undefined;
};

/** What distinguishes one card from another, for the avoid list. */
const fingerprint = (card: DraftCard) => (card.kind === 'verse' ? card.reference ?? card.osis ?? '' : card.text ?? '');

export const handleRedraftRequest = async (request: Request, deps: RedraftDeps): Promise<Response> => {
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
  if (!limit.ok) return json(429, { error: 'rate_limited' });

  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return fail(400, 'invalid_json');
  }
  if (!body || typeof body !== 'object' || Array.isArray(body)) return fail(400, 'invalid_json');

  const { extractedText, kind, avoid, passage, title, preacher } = body as Record<string, unknown>;
  if (typeof extractedText !== 'string' || !extractedText.trim()) return fail(400, 'missing_text');
  if (extractedText.length > MAX_TEXT_CHARS) return fail(400, 'text_too_long');
  if (kind !== undefined && !(CARD_KINDS as readonly string[]).includes(kind as string)) return fail(400, 'unknown_kind');

  const avoidList = Array.isArray(avoid)
    ? avoid.filter((a): a is string => typeof a === 'string').slice(0, MAX_AVOID).map((a) => a.trim()).filter(Boolean)
    : [];

  let rawCards: unknown[];
  try {
    const result = await draftPage(
      { kind: 'text', text: extractedText },
      // preacher is an attribution applied at validation, not part of the prompt
      { passage: meta(passage), title: meta(title) },
      { apiKey: deps.geminiApiKey, model: deps.model, fetchImpl: deps.fetchImpl, retryDelayMs: deps.retryDelayMs },
    );
    rawCards = result.rawCards;
  } catch (error) {
    const code = error instanceof CardsError ? error.code : 'failed';
    return json(code === 'rate_limited' ? 429 : 502, { error: code });
  }

  // Exactly the rules the full draft obeys: a quote must still be a span of the
  // notes, a verse still leaves as a reference only.
  const { cards } = validateGeneratedCards(rawCards, { sourceText: extractedText, preacher: meta(preacher), page: 0 });

  const candidate = cards.find(
    (card) => (kind === undefined || card.kind === (kind as CardKind)) && !avoidList.includes(fingerprint(card)),
  );
  if (!candidate) return fail(422, 'no_card');

  return json(200, { card: candidate });
};
