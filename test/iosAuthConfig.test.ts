// TKL-1041: Release bundles the studio prod pool config (amplify_outputs.prod.json),
// Debug stays on dev (amplify_outputs.dev.json), and the committed Xcode project
// includes both resources with per-configuration exclusions.
import { readFileSync } from 'fs';
import { join } from 'path';
import { describe, expect, test } from 'vitest';

const root = join(__dirname, '..');
const resourcesDir = join(root, 'ios/App/Resources');
const projectYml = readFileSync(join(root, 'ios/App/project.yml'), 'utf8');
const pbxproj = readFileSync(join(root, 'ios/App/ConfessionalChristianity.xcodeproj/project.pbxproj'), 'utf8');
const authService = readFileSync(join(root, 'ios/App/Sources/Auth/AuthService.swift'), 'utf8');

describe('iOS Amplify auth configuration', () => {
  test('prod config points at Studio-prod confessional client', () => {
    const prod = JSON.parse(readFileSync(join(resourcesDir, 'amplify_outputs.prod.json'), 'utf8'));
    expect(prod.version).toBe('1.4');
    expect(prod.auth).toMatchObject({
      aws_region: 'us-east-1',
      user_pool_id: 'us-east-1_80qmmpRpD',
      user_pool_client_id: '138ua04t4vtitttt5uaq72iji2',
      username_attributes: ['email'],
      user_verification_types: ['email'],
    });
  });

  test('dev config stays on ConfessionalChristianity-dev and distinct from prod', () => {
    const dev = JSON.parse(readFileSync(join(resourcesDir, 'amplify_outputs.dev.json'), 'utf8'));
    const prod = JSON.parse(readFileSync(join(resourcesDir, 'amplify_outputs.prod.json'), 'utf8'));
    expect(dev.auth).toMatchObject({
      aws_region: 'us-east-1',
      user_pool_id: 'us-east-1_Tbhzx2V7a',
      user_pool_client_id: '1qibu96101fa0n6iaiuqmpklq1',
    });
    expect(dev.auth.user_pool_id).not.toBe(prod.auth.user_pool_id);
    expect(dev.auth.user_pool_client_id).not.toBe(prod.auth.user_pool_client_id);
  });

  test('generated Xcode project bundles prod in Release and dev in Debug', () => {
    expect(pbxproj).toContain('amplify_outputs.prod.json in Resources');
    expect(pbxproj).toContain('amplify_outputs.dev.json in Resources');
    expect(pbxproj).toContain('EXCLUDED_SOURCE_FILE_NAMES = amplify_outputs.prod.json;');
    expect(pbxproj).toContain('EXCLUDED_SOURCE_FILE_NAMES = amplify_outputs.dev.json;');
  });

  test('project.yml and AuthService have no stale prod-missing comments', () => {
    expect(projectYml).not.toMatch(/TKL-893|TKL-1037/);
    expect(authService).not.toMatch(/TKL-893|TKL-1037/);
  });
});
