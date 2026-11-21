// TKL-814: pure pieces of scripts/ios/release.mjs. Runs under `npm test` (vitest).
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';
import {
  APP_ID,
  archiveArgs,
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

  it('exports with provisioning updates and never with the ASC key (TKL-880)', () => {
    const args = exportArgs({ archivePath: 'a', exportPath: 'b', plistPath: 'c' });
    expect(args).toEqual(['-exportArchive', '-archivePath', 'a', '-exportPath', 'b', '-exportOptionsPlist', 'c', '-allowProvisioningUpdates']);
    expect(args.join(' ')).not.toMatch(/authenticationKey/);
  });

  it('uploads on a real run and exports locally on a dry run', () => {
    expect(exportPlist({ upload: true })).toContain('<key>destination</key><string>upload</string>');
    expect(exportPlist({ upload: false })).toContain('<key>destination</key><string>export</string>');
    expect(exportPlist({ upload: true })).toContain('<string>app-store-connect</string>');
    expect(exportPlist({ upload: true })).toContain('<string>7GZKY29XJH</string>');
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
    expect(releaseSource).not.toMatch(/authenticationKey/);
  });
});
