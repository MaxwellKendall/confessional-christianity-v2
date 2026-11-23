import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

const source = file => readFileSync(new URL(`../../ios/App/Sources/${file}`, import.meta.url), 'utf8');

describe('final onboarding prototype', () => {
  it('orders the title, both scripture and demo pairs, and the first action', () => {
    expect(source('Onboarding/OnboardingView.swift')).toMatch(
      /case \.title:[\s\S]*case \.teachingScripture:[\s\S]*case \.catechism:[\s\S]*case \.sabbathScripture:[\s\S]*case \.sermon:[\s\S]*case \.firstAction:/
    );
  });

  it('persists completion and connects both guest routes to the real app', () => {
    const root = source('RootView.swift');
    expect(root).toContain('@AppStorage("didCompleteOnboarding")');
    expect(root).toContain('onBegin: beginCatechism');
    expect(root).toContain('startsCapture: $startsCapture');
    expect(root).toContain('todayPath.append(LibraryRoute.session(');
    expect(source('LordsDay/LordsDayTabView.swift')).toContain('.onChange(of: startsCapture, initial: true)');
  });

  it('binds the sign-in code prompt and Verify to the address the code was sent to', () => {
    const sheet = source('Onboarding/OnboardingSignInView.swift');
    expect(sheet).toContain('auth.phase.pendingEmail');
    expect(sheet).toContain('auth.verifyCode(code)');
    expect(sheet).not.toContain('auth.verify(email: email');
    expect(sheet).not.toContain('sent to \\(email)');
    expect(sheet).toMatch(/TextField\("Email", text: \$email\)[\s\S]*?\.disabled\(isSending\)/);
  });
});
