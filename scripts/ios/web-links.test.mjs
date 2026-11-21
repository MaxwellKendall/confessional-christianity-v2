import { readFileSync } from 'node:fs';
import { expect, test } from 'vitest';

test('iOS links and ESV requests share the custom domain', () => {
  const sources = new URL('../../ios/App/Sources/', import.meta.url);
  const links = readFileSync(new URL('Support/WebLinks.swift', sources), 'utf8');
  const esv = readFileSync(new URL('Scripture/EsvClient.swift', sources), 'utf8');

  expect(links).toMatch(/static let base = "https:\/\/confessionalchristianity\.com"/);
  expect(esv).toContain('private static let baseURL = "\\(WebLinks.base)/api/esv"');
});
