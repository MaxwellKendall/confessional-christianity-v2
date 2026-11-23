import { readFileSync, readdirSync } from 'node:fs';
import { expect, test } from 'vitest';

const sources = new URL('../../ios/App/Sources/', import.meta.url);

test('iOS links and ESV requests share the custom domain', () => {
  const links = readFileSync(new URL('Support/WebLinks.swift', sources), 'utf8');
  const esv = readFileSync(new URL('Scripture/EsvClient.swift', sources), 'utf8');
  const cards = readFileSync(new URL('LordsDay/CardsGenerator.swift', sources), 'utf8');

  expect(links).toMatch(/static let base = "https:\/\/confessionalchristianity\.com"/);
  expect(esv).toContain('private static let baseURL = "\\(WebLinks.base)/api/esv"');
  expect(cards).toContain('URL(string: "\\(WebLinks.base)/api/lords-day/cards")!');
});

test('no app source calls a vercel.app host', () => {
  const files = readdirSync(sources, { recursive: true }).filter((f) => String(f).endsWith('.swift'));
  const offenders = files.filter((f) => readFileSync(new URL(String(f), sources), 'utf8').includes('vercel.app'));
  expect(offenders).toEqual([]);
});
