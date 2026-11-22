// TKL-938: the app's Chapel tokens are the approved prototype's (TKL-885), and
// the side-by-side check can render its states. Runs under `npm test` (vitest).
import { readFileSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';
import { parseState, prototypePage } from '../../ios/scripts/prototype-shots/page.mjs';

const read = (p) => readFileSync(fileURLToPath(new URL(`../../${p}`, import.meta.url)), 'utf8');
const swiftFiles = (dir) => readdirSync(fileURLToPath(new URL(`../../${dir}`, import.meta.url)), { recursive: true })
  .filter((f) => String(f).endsWith('.swift'))
  .map((f) => `${dir}/${f}`);

const sources = 'ios/App/Sources';
const designSystem = read(`${sources}/DesignSystem.swift`);
const prototype = read('ios/scripts/prototype-shots/prototype.html');
const cssBlock = (selector) => prototype.match(new RegExp(`\\n${selector.replace('.', '\\.')}\\{([\\s\\S]*?)\\n\\}`))[1];
const cssHex = (block) => Object.fromEntries([...block.matchAll(/--([\w-]+):#([0-9a-f]{6})/g)].map((m) => [m[1], m[2]]));
const swiftName = (token) => `cc${token.split('-').map((w) => w[0].toUpperCase() + w.slice(1)).join('')}`;

describe('Chapel tokens', () => {
  const light = cssHex(cssBlock(':root'));
  const dark = cssHex(cssBlock('.dark'));

  it('reads all twelve colours from the prototype', () => {
    expect(Object.keys(light)).toHaveLength(12);
    expect(Object.keys(dark)).toEqual(Object.keys(light));
  });

  it.each(Object.keys(light))('%s has the prototype\'s light and dark values', (token) => {
    expect(designSystem.toLowerCase()).toContain(
      `static let ${swiftName(token)} = Color(light: 0x${light[token]}, dark: 0x${dark[token]})`.toLowerCase(),
    );
  });

  it.each([
    ['xs', 4], ['s', 8], ['m', 12], ['l', 16], ['xl', 24], ['xxl', 32], ['xxxl', 48], ['gutter', 20],
    ['sheet', 22], ['card', 14], ['control', 12], ['tabBar', 26], ['buttonHeight', 50],
  ])('%s is %d', (name, value) => {
    expect(designSystem).toMatch(new RegExp(`static let ${name}: CGFloat = ${value}$`, 'm'));
  });

  it('has the type roles', () => {
    for (const role of ['ccTitle', 'ccH2', 'ccLabelCaps', 'ccReading', 'ccUI']) {
      expect(designSystem).toMatch(new RegExp(`static (let|var|func) ${role}\\b`));
    }
  });

  it('no longer mirrors globals.css or holds the cream palette', () => {
    expect(designSystem).not.toContain('globals.css');
    const cream = /0x(e9e6dd|faf9f6|211e19|5c574c|8a8378|ddd8cd|e2ddd0|f4f2ea|c9c4b6|ab7e2e|c9a468|ede7d8)\b/i;
    for (const file of [...swiftFiles(sources), ...swiftFiles('ios/App/Widget/Sources')]) {
      expect(read(file), file).not.toMatch(cream);
    }
  });
});

describe('Today and the tab bar', () => {
  const files = [
    ...swiftFiles(`${sources}/Home`),
    ...['Support/FloatingTabBarView.swift', 'Support/TabIcons.swift', 'RootView.swift'].map((f) => `${sources}/${f}`),
  ];

  it.each(files)('%s has no one-off colours or fonts', (file) => {
    expect(read(file)).not.toMatch(/Color\(hex|Color\.(white|black|gray)|\.font\(\.system\(size/);
  });
});

describe('prototype shots', () => {
  it('parses a state name', () => {
    expect(parseState('today-full-light')).toEqual({
      screen: 'today', state: 'full', day: 'thu', signed: '0', theme: 'light',
    });
    expect(parseState('settings-empty-sun-signed-dark')).toEqual({
      screen: 'settings', state: 'empty', day: 'sun', signed: '1', theme: 'dark',
    });
  });

  it.each(['today', 'today-full', 'home-full-light', 'today-busy-light', 'today-full-mon-dark', 'today-full-light;x'])(
    'rejects %s',
    (name) => expect(() => parseState(name)).toThrow(/state/i),
  );

  it('builds an offline page in that state', () => {
    const html = prototypePage(prototype, 'today-empty-dark', 'file:///fonts/');
    expect(html).not.toContain('fonts.googleapis.com');
    expect(html).toContain('file:///fonts/Marcellus-Regular.ttf');
    expect(html).toContain('"state":"empty"');
    expect(html).toContain('"theme":"dark"');
  });
});
