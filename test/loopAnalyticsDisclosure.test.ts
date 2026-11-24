// TKL-947: the iOS app's Lord's Day counts go to PostHog. The privacy policy and
// the app's privacy manifest must both say so, and say what is never sent.
import { readFileSync } from 'fs';
import { join } from 'path';
import { describe, expect, test } from 'vitest';

const root = join(__dirname, '..');
const policy = readFileSync(join(root, 'src/app/(column)/privacy/page.tsx'), 'utf8');
const manifest = readFileSync(join(root, 'ios/App/Sources/PrivacyInfo.xcprivacy'), 'utf8');
const sender = readFileSync(join(root, 'ios/DomainKit/Sources/DomainKit/LoopAnalytics.swift'), 'utf8');

describe('privacy policy', () => {
  test('no longer claims there are no analytics', () => {
    expect(policy).not.toMatch(/no analytics/i);
    expect(policy).not.toMatch(/doesn't collect any/i);
  });

  test('names the provider and each of the three counts', () => {
    expect(policy).toContain('PostHog');
    expect(policy).toContain('A sermon kept');
    expect(policy).toContain('A day opened');
    expect(policy).toContain('A card shared');
  });

  test('lists what is never sent', () => {
    for (const word of ['notes', "cards' words", 'photos', 'Bible\nreferences', 'preacher', 'church', 'email']) {
      expect(policy).toContain(word);
    }
    expect(policy).toMatch(/are never sent/);
  });
});

describe('iOS privacy manifest', () => {
  const entries = [...manifest.matchAll(/<dict>\s*<key>NSPrivacyCollectedDataType<\/key>([\s\S]*?)<\/dict>/g)].map((m) => m[0]);

  test('declares product interaction and a device-level id, unlinked, untracked, for analytics only', () => {
    const types = entries.map((e) => e.match(/<string>(NSPrivacyCollectedDataType[A-Za-z]+)<\/string>/)?.[1]);
    expect(types.sort()).toEqual(['NSPrivacyCollectedDataTypeDeviceID', 'NSPrivacyCollectedDataTypeProductInteraction']);
    for (const e of entries) {
      expect(e).toMatch(/NSPrivacyCollectedDataTypeLinked<\/key>\s*<false\/>/);
      expect(e).toMatch(/NSPrivacyCollectedDataTypeTracking<\/key>\s*<false\/>/);
      expect([...e.matchAll(/<string>(NSPrivacyCollectedDataTypePurpose[A-Za-z]+)<\/string>/g)].map((m) => m[1])).toEqual([
        'NSPrivacyCollectedDataTypePurposeAnalytics',
      ]);
    }
    expect(manifest).toMatch(/NSPrivacyTracking<\/key>\s*<false\/>/);
  });

  test('declares the UserDefaults access the install id needs', () => {
    expect(manifest).toContain('NSPrivacyAccessedAPICategoryUserDefaults');
    expect(manifest).toContain('CA92.1');
  });

  test('matches the events the app actually sends', () => {
    expect(sender).toContain('"lords_day_sermon_kept"');
    expect(sender).toContain('"lords_day_day_opened"');
    expect(sender).toContain('"lords_day_card_shared"');
  });
});
