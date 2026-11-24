// TKL-992: email-code accounts, account sync and drafting cards from sermon-note
// photos (Google Gemini) must be in the privacy policy and the iOS privacy
// manifest before they reach users.
import { readFileSync } from 'fs';
import { join } from 'path';
import { describe, expect, test } from 'vitest';

const root = join(__dirname, '..');
const policy = readFileSync(join(root, 'src/app/(column)/privacy/page.tsx'), 'utf8').replace(/\s+/g, ' ');
const manifest = readFileSync(join(root, 'ios/App/Sources/PrivacyInfo.xcprivacy'), 'utf8');

describe('privacy policy: accounts', () => {
  test('no longer claims there are no accounts or email addresses', () => {
    expect(policy).not.toMatch(/no user accounts/i);
    expect(policy).not.toMatch(/no email addresses/i);
    expect(policy).not.toMatch(/does not require an account/i);
    expect(policy).not.toMatch(/collects no personal information/i);
  });

  test('describes the email address, the sign-in codes and what syncs', () => {
    expect(policy).toContain('## Accounts');
    expect(policy).toMatch(/email address/i);
    expect(policy).toMatch(/one-time sign-in code/i);
    expect(policy).toMatch(/no password/i);
    for (const synced of ["children's names and ages", 'catechism progress', 'sermon notes', 'cards']) {
      expect(policy).toContain(synced);
    }
    expect(policy).toMatch(/optional/i);
  });
});

describe('privacy policy: drafting cards from photos', () => {
  test('names Google Gemini and says photos are used only to draft cards and not stored online', () => {
    expect(policy).toContain('Google Gemini');
    expect(policy).toMatch(/only to draft (the )?cards/i);
    expect(policy).toMatch(/photos are not stored online/i);
  });

  test('says the drafted text and cards are stored with the account when signed in', () => {
    expect(policy).toMatch(/drafted text and cards are stored with your account when you're signed in/i);
  });
});

describe('iOS privacy manifest: accounts and drafting', () => {
  const entries = [...manifest.matchAll(/<dict>\s*<key>NSPrivacyCollectedDataType<\/key>([\s\S]*?)<\/dict>/g)].map((m) => m[0]);
  const entryFor = (type: string) => entries.find((e) => e.includes(`<string>${type}</string>`));

  test.each([
    'NSPrivacyCollectedDataTypeEmailAddress',
    'NSPrivacyCollectedDataTypeOtherUserContent',
    'NSPrivacyCollectedDataTypePhotosorVideos',
  ])('declares %s linked, not tracking, for app functionality only', (type) => {
    const e = entryFor(type);
    expect(e, `${type} is declared`).toBeDefined();
    expect(e).toMatch(/NSPrivacyCollectedDataTypeLinked<\/key>\s*<true\/>/);
    expect(e).toMatch(/NSPrivacyCollectedDataTypeTracking<\/key>\s*<false\/>/);
    expect([...e!.matchAll(/<string>(NSPrivacyCollectedDataTypePurpose[A-Za-z]+)<\/string>/g)].map((m) => m[1])).toEqual([
      'NSPrivacyCollectedDataTypePurposeAppFunctionality',
    ]);
  });

  test('declares each data type once', () => {
    const types = entries.map((e) => e.match(/<string>(NSPrivacyCollectedDataType[A-Za-z]+)<\/string>/)?.[1]);
    expect(new Set(types).size).toBe(types.length);
  });
});
