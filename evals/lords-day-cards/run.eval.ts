import { mkdirSync, readFileSync, writeFileSync } from 'fs';
import path from 'path';
import { expect, test } from 'vitest';

import { normalizeForMatch, type DraftCard } from '@/lib/lordsDay/cards';
import { cardsModel } from '@/lib/lordsDay/gemini';
import { handleCardsRequest } from '@/lib/lordsDay/handler';
import { createRateLimiter } from '@/lib/lordsDay/rateLimit';

// Golden eval for the photo → cards generator (TKL-861). Calls Gemini for real
// (costs money: ~$0.01 per photo at the recorded rates). Run from the repo root:
//   set -a; source ~/dev/.secrets.env; set +a; npm run eval:cards
//   GEMINI_CARDS_MODEL=gemini-3.5-flash-lite npm run eval:cards   # compare a model
// Writes evals/lords-day-cards/results/<model>.json and prints per-case pass and a total.
//
// A case passes when: (1) it drafts at least 3 cards, (2) a Verse card names the
// sermon passage (book and chapter), and (3) Key point / Quote cards carry at least
// 2 of its 4 key spans. Every card is one of the three kinds by construction.

const DIR = __dirname;

interface Case {
  id: string;
  photo: string;
  passage: string;
  otherPassages: string[];
  keySpans: string[];
}

const { cases } = JSON.parse(readFileSync(path.join(DIR, 'truth.json'), 'utf8')) as { cases: Case[] };

const bookChapter = (osis: string) => osis.split('-')[0].split('.').slice(0, 2).join('.');

const spanFound = (span: string, haystack: string) =>
  span.split('|').some((alt) => haystack.includes(normalizeForMatch(alt)));

const runCase = async (c: Case, model: string, apiKey: string) => {
  const data = readFileSync(path.join(DIR, c.photo)).toString('base64');
  const started = Date.now();
  const response = await handleCardsRequest(
    new Request('http://eval/api/lords-day/cards', {
      method: 'POST',
      headers: { authorization: 'Bearer eval', 'content-type': 'application/json' },
      body: JSON.stringify({ images: [{ data, mimeType: 'image/jpeg' }] }),
    }),
    {
      geminiApiKey: apiKey,
      model,
      verifyAccessToken: async () => ({ sub: 'eval' }),
      limiter: createRateLimiter({ limit: 1000, windowMs: 1000 }),
    },
  );
  const events = (await response.text())
    .split('\n')
    .filter(Boolean)
    .map((line) => JSON.parse(line));
  const seconds = (Date.now() - started) / 1000;
  const firstCardIndex = events.findIndex((e) => e.type === 'card');
  const page = events.find((e) => e.type === 'page');
  const error = events.find((e) => e.type === 'error');
  const done = events.find((e) => e.type === 'done') ?? { cards: [], rejected: 0, costUsd: 0 };
  const cards: DraftCard[] = done.cards;

  const verses = cards.filter((k) => k.kind === 'verse').map((k) => bookChapter(k.osis!));
  const prose = normalizeForMatch(
    cards
      .filter((k) => k.kind !== 'verse')
      .map((k) => k.text)
      .join(' \n '),
  );
  const transcript = normalizeForMatch(page?.extractedText ?? '');
  const spansInCards = c.keySpans.filter((s) => spanFound(s, prose));
  const spansInTranscript = c.keySpans.filter((s) => spanFound(s, transcript));
  const passageFound = verses.includes(c.passage);
  const otherFound = c.otherPassages.filter((p) => verses.includes(p));

  const checks = {
    atLeast3Cards: cards.length >= 3,
    passageFound,
    keySpans: spansInCards.length >= 2,
  };
  return {
    id: c.id,
    pass: Object.values(checks).every(Boolean),
    checks,
    error: error ? `${error.code}: ${error.message}` : undefined,
    kinds: cards.map((k) => k.kind),
    verses,
    otherPassagesFound: `${otherFound.length}/${c.otherPassages.length}`,
    spansInCards: `${spansInCards.length}/${c.keySpans.length}`,
    spansInTranscript: `${spansInTranscript.length}/${c.keySpans.length}`,
    quotesKept: cards.filter((k) => k.kind === 'quote').length,
    rejected: done.rejected,
    costUsd: done.costUsd,
    seconds,
    streamedBeforeDone: firstCardIndex >= 0 && firstCardIndex < events.findIndex((e) => e.type === 'done'),
    cards,
  };
};

test(
  'lords-day cards eval',
  async () => {
    const apiKey = process.env.GEMINI_API_KEY;
    if (!apiKey) throw new Error('GEMINI_API_KEY is not set (source ~/dev/.secrets.env)');
    const model = cardsModel();
    const only = process.env.EVAL_CASES?.split(',');
    const selected = only ? cases.filter((c) => only.includes(c.id)) : cases;

    // 4 at a time
    const results: Awaited<ReturnType<typeof runCase>>[] = [];
    for (let i = 0; i < selected.length; i += 4) {
      results.push(...(await Promise.all(selected.slice(i, i + 4).map((c) => runCase(c, model, apiKey)))));
    }

    const passed = results.filter((r) => r.pass).length;
    const cost = results.reduce((s, r) => s + r.costUsd, 0);
    const rows = results.map(
      (r) =>
        `${r.pass ? 'PASS' : 'FAIL'}  ${r.id}  cards=${r.kinds.length} passage=${r.checks.passageFound ? 'y' : 'n'} spans=${r.spansInCards} transcript=${r.spansInTranscript} other=${r.otherPassagesFound} quotes=${r.quotesKept} rejected=${r.rejected} $${r.costUsd.toFixed(4)} ${r.seconds.toFixed(1)}s${r.error ? ` ERROR ${r.error}` : ''}`,
    );
    const summary = {
      model,
      date: new Date().toISOString(),
      passed,
      total: results.length,
      costUsdTotal: cost,
      costUsdPerPhoto: cost / results.length,
      medianSeconds: [...results.map((r) => r.seconds)].sort((a, b) => a - b)[Math.floor(results.length / 2)],
      rejectedTotal: results.reduce((s, r) => s + r.rejected, 0),
    };
    console.log(`\n${rows.join('\n')}\n\nTOTAL ${passed}/${results.length}  model=${model}  cost=$${cost.toFixed(4)} ($${summary.costUsdPerPhoto.toFixed(4)}/photo)  median ${summary.medianSeconds.toFixed(1)}s\n`);

    mkdirSync(path.join(DIR, 'results'), { recursive: true });
    writeFileSync(path.join(DIR, 'results', `${model}.json`), `${JSON.stringify({ summary, results }, null, 2)}\n`);
    // the run is a report, not a gate; it fails only if nothing came back at all
    expect(results.some((r) => r.kinds.length > 0)).toBe(true);
  },
  10 * 60 * 1000,
);
