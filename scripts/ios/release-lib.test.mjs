// TKL-814: pure pieces of scripts/ios/release.mjs. Runs under `npm test` (vitest).
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';
import {
  APP_ID,
  altoolArgs,
  altoolFailed,
  archiveArgs,
  cloudSigningDenied,
  exportArgs,
  exportPlist,
  highestBuildNumber,
  parseArgs,
  processingVerdict,
  readVersions,
  redact,
  setVersions,
} from './release-lib.mjs';

const projectYml = readFileSync(fileURLToPath(new URL('../../ios/App/project.yml', import.meta.url)), 'utf8');
const releaseSource = readFileSync(fileURLToPath(new URL('./release.mjs', import.meta.url)), 'utf8');

const twoTargets = `targets:
  App:
    settings:
      base:
        MARKETING_VERSION: "1.1"
        CURRENT_PROJECT_VERSION: "3"
  Widget:
    settings:
      base:
        MARKETING_VERSION: "1.1"
        CURRENT_PROJECT_VERSION: "3"
`;

describe('parseArgs', () => {
  it('defaults to a real run with no marketing change', () => {
    expect(parseArgs([])).toEqual({ dryRun: false, marketingVersion: undefined, help: false });
  });

  it('reads --dry-run and --marketing-version in either form', () => {
    expect(parseArgs(['--', '--dry-run', '--marketing-version', '1.2'])).toEqual({ dryRun: true, marketingVersion: '1.2', help: false });
    expect(parseArgs(['--marketing-version=1.2.1']).marketingVersion).toBe('1.2.1');
  });

  it('rejects a malformed marketing version and unknown flags', () => {
    expect(() => parseArgs(['--marketing-version', 'v1'])).toThrow(/marketing version/);
    expect(() => parseArgs(['--marketing-version'])).toThrow(/marketing version/);
    expect(() => parseArgs(['--submit'])).toThrow(/Unknown argument/);
  });
});

describe('readVersions / setVersions', () => {
  it('reads the versions from the real project.yml', () => {
    const v = readVersions(projectYml);
    expect(v.marketing).toMatch(/^\d+(\.\d+){1,2}$/);
    expect(Number(v.build)).toBeGreaterThanOrEqual(3);
  });

  it('sets the build number on every target, keeping the rest of the file', () => {
    const out = setVersions(twoTargets, { build: 7 });
    expect(out.match(/CURRENT_PROJECT_VERSION: "7"/g)).toHaveLength(2);
    expect(out.match(/MARKETING_VERSION: "1.1"/g)).toHaveLength(2);
    expect(out.replace(/"7"/g, '"3"')).toBe(twoTargets);
  });

  it('sets the marketing version on every target when given', () => {
    const out = setVersions(twoTargets, { build: 4, marketing: '1.2' });
    expect(out.match(/MARKETING_VERSION: "1.2"/g)).toHaveLength(2);
    expect(readVersions(out)).toEqual({ marketing: '1.2', build: '4' });
  });

  it('refuses targets that disagree, or a file without the settings', () => {
    expect(() => readVersions(twoTargets.replace('CURRENT_PROJECT_VERSION: "3"', 'CURRENT_PROJECT_VERSION: "2"'))).toThrow(/disagree/);
    expect(() => readVersions('name: x\n')).toThrow(/missing/);
  });
});

describe('highestBuildNumber', () => {
  it('takes the numeric maximum, expired builds included', () => {
    const builds = [
      { attributes: { version: '9', expired: true } },
      { attributes: { version: '10', expired: false } },
      { attributes: { version: '2' } },
    ];
    expect(highestBuildNumber(builds)).toBe(10);
    expect(highestBuildNumber([])).toBe(0);
  });
});

describe('processingVerdict', () => {
  it('maps App Store Connect processing states', () => {
    expect(processingVerdict(undefined)).toBe('waiting');
    expect(processingVerdict({ attributes: { processingState: 'PROCESSING' } })).toBe('waiting');
    expect(processingVerdict({ attributes: { processingState: 'VALID' } })).toBe('valid');
    expect(processingVerdict({ attributes: { processingState: 'FAILED' } })).toBe('failed');
    expect(processingVerdict({ attributes: { processingState: 'INVALID' } })).toBe('failed');
  });
});

describe('xcodebuild arguments', () => {
  it('archives Release for devices with provisioning updates', () => {
    const args = archiveArgs({ archivePath: 'build/release/CC.xcarchive' });
    expect(args).toEqual(expect.arrayContaining(['archive', '-scheme', 'ConfessionalChristianity', '-configuration', 'Release', '-allowProvisioningUpdates']));
    expect(args.join(' ')).toContain('generic/platform=iOS');
  });

  it('pins version overrides on a dry run so project.yml is untouched', () => {
    const args = archiveArgs({ archivePath: 'a', overrides: { build: 9, marketing: '1.2' } });
    expect(args).toContain('CURRENT_PROJECT_VERSION=9');
    expect(args).toContain('MARKETING_VERSION=1.2');
  });

  const auth = { keyId: 'KEY123', issuerId: 'ISS-456', keyPath: '/keys/AuthKey_KEY123.p8' };

  it('exports with provisioning updates through the Xcode account when no key is given', () => {
    const args = exportArgs({ archivePath: 'a', exportPath: 'b', plistPath: 'c' });
    expect(args).toEqual(['-exportArchive', '-archivePath', 'a', '-exportPath', 'b', '-exportOptionsPlist', 'c', '-allowProvisioningUpdates']);
  });

  it('exports with the ASC key when given one', () => {
    const args = exportArgs({ archivePath: 'a', exportPath: 'b', plistPath: 'c', auth });
    expect(args.slice(0, 8)).toEqual(['-exportArchive', '-archivePath', 'a', '-exportPath', 'b', '-exportOptionsPlist', 'c', '-allowProvisioningUpdates']);
    expect(args.slice(8)).toEqual(['-authenticationKeyPath', '/keys/AuthKey_KEY123.p8', '-authenticationKeyID', 'KEY123', '-authenticationKeyIssuerID', 'ISS-456']);
  });

  it('always exports a local .ipa: the upload is a separate, key-authenticated step', () => {
    const plist = exportPlist();
    expect(plist).toContain('<key>destination</key><string>export</string>');
    expect(plist).not.toContain('<string>upload</string>');
    expect(plist).toContain('<string>app-store-connect</string>');
    expect(plist).toContain('<string>7GZKY29XJH</string>');
  });

  it('recognises the cloud-signing permission error, and only that', () => {
    expect(cloudSigningDenied("error: exportArchive Cloud signing permission error\n  You haven't been given access to cloud-managed distribution certificates.")).toBe(true);
    expect(cloudSigningDenied('error: exportArchive No signing certificate "iOS Distribution" found')).toBe(true);
    expect(cloudSigningDenied('error: exportArchive The data couldn’t be read because it isn’t in the correct format.')).toBe(false);
  });
});

describe('altool arguments (upload authenticated by the ASC API key)', () => {
  const auth = { keyId: 'KEY123', issuerId: 'ISS-456', keyPath: '/keys/AuthKey_KEY123.p8' };
  const key = ['--api-key', 'KEY123', '--api-issuer', 'ISS-456', '--p8-file-path', '/keys/AuthKey_KEY123.p8'];

  it('validates the .ipa with the key', () => {
    expect(altoolArgs({ action: 'validate', ipa: 'x.ipa', auth })).toEqual(['altool', '--validate-app', '-f', 'x.ipa', '-t', 'ios', ...key, '--output-format', 'json']);
  });

  it('uploads the .ipa with the key', () => {
    expect(altoolArgs({ action: 'upload', ipa: 'x.ipa', auth })).toEqual(['altool', '--upload-app', '-f', 'x.ipa', '-t', 'ios', ...key, '--output-format', 'json']);
  });

  it('refuses any other action and a missing key', () => {
    expect(() => altoolArgs({ action: 'submit', ipa: 'x.ipa', auth })).toThrow(/action/);
    expect(() => altoolArgs({ action: 'upload', ipa: 'x.ipa', auth: { keyId: 'K' } })).toThrow(/key/);
  });

  it('treats a non-zero exit or a reported error as failure', () => {
    expect(altoolFailed(0, '{"success-message":"No errors uploading archive"}')).toBe(false);
    expect(altoolFailed(1, '')).toBe(true);
    expect(altoolFailed(0, '{"product-errors":[{"message":"Invalid bundle"}]}')).toBe(true);
    expect(altoolFailed(0, '*** Error: Unable to authenticate')).toBe(true);
  });
});

describe('redact', () => {
  it('hides secret values', () => {
    expect(redact('key ABCD1234 issuer xyz', ['ABCD1234', ''])).toBe('key •••• issuer xyz');
  });
});

describe('release.mjs never submits or releases', () => {
  it('only reads from App Store Connect', () => {
    expect(APP_ID).toBe('6797692942');
    expect(releaseSource).not.toMatch(/method:\s*['"](POST|PATCH|DELETE|PUT)/);
    expect(releaseSource).not.toMatch(/reviewSubmissions|appStoreVersionSubmissions|appStoreVersionReleaseRequests|betaAppReviewSubmissions/);
  });

  it('uploads only through altool with the ASC key, never through an Xcode upload destination', () => {
    expect(releaseSource).toMatch(/altoolArgs\(\{ action: 'upload'/);
    expect(releaseSource).not.toMatch(/destination.*upload|exportPlist\(\{\s*upload/);
  });
});
