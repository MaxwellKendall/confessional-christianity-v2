'use client';

import { useEffect, useReducer, useRef, useState } from 'react';

import {
  friendlyAuthError,
  restoreSession,
  saveSession,
  sendCode,
  signOutSession,
  verifyCode,
} from '@/lib/account/cognitoClient';
import type { PublicCognitoConfig } from '@/lib/account/config';
import {
  accountReducer,
  initialAccountState,
  normalizeCode,
  normalizeEmail,
  type AccountError,
  type AccountUser,
} from '@/lib/account/machine';

interface AccountClientProps {
  config: PublicCognitoConfig | null;
}

const errorMessage = (error: AccountError | null): string | null => {
  if (!error) return null;
  switch (error.kind) {
    case 'invalidEmail':
      return 'Enter a valid email address.';
    case 'invalidCode':
      return 'Enter the 6-digit or 8-digit code from your email.';
    case 'sendFailed':
    case 'verifyFailed':
      return error.message;
  }
};

async function fetchVerifiedUser(idToken: string): Promise<AccountUser | null> {
  try {
    const res = await fetch('/api/account/me', {
      headers: { Authorization: `Bearer ${idToken}` },
      cache: 'no-store',
    });
    if (!res.ok) return null;
    const data = (await res.json()) as { sub?: unknown; email?: unknown };
    if (typeof data.sub !== 'string' || !data.sub) return null;
    return {
      sub: data.sub,
      email: typeof data.email === 'string' && data.email ? data.email : null,
    };
  } catch {
    return null;
  }
}

export function AccountClient({ config }: AccountClientProps) {
  const [state, dispatch] = useReducer(accountReducer, initialAccountState);
  const [emailInput, setEmailInput] = useState('');
  const [codeInput, setCodeInput] = useState('');
  const [serverVerified, setServerVerified] = useState(false);
  const authSessionRef = useRef<string | undefined>(undefined);

  useEffect(() => {
    if (!config) return;
    let cancelled = false;
    (async () => {
      const restored = await restoreSession(config);
      if (cancelled) return;
      if (!restored) {
        dispatch({ type: 'restored', user: null });
        return;
      }
      dispatch({ type: 'restored', user: restored.user });
      const verified = await fetchVerifiedUser(restored.tokens.idToken);
      if (cancelled || !verified) return;
      setServerVerified(true);
      dispatch({
        type: 'sessionUpdated',
        user: {
          sub: verified.sub,
          email: verified.email ?? restored.user.email,
        },
      });
    })();
    return () => {
      cancelled = true;
    };
  }, [config]);

  if (!config) {
    return (
      <div className="px-5 pt-6 pb-10">
        <h1 className="heading-page text-center">Account</h1>
        <p className="mt-6 text-center text-[14.5px] italic leading-relaxed text-ink-2">
          Accounts are coming soon.
        </p>
      </div>
    );
  }

  const { phase, error } = state;
  const errText = errorMessage(error);
  const inFlight =
    phase.kind === 'sendingCode' || phase.kind === 'verifying' || phase.kind === 'signingIn';

  const handleRequestCode = async (rawEmail: string) => {
    const normalized = normalizeEmail(rawEmail);
    dispatch({ type: 'requestCode', email: rawEmail });
    if (!normalized) return;

    authSessionRef.current = undefined;
    try {
      const result = await sendCode(config, normalized);
      authSessionRef.current = result.session;
      setCodeInput('');
      dispatch({ type: result.purpose === 'signUp' ? 'signUpCodeSent' : 'codeSent' });
    } catch (err) {
      dispatch({ type: 'sendFailed', message: friendlyAuthError(err) });
    }
  };

  const handleEmailSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (inFlight) return;
    void handleRequestCode(emailInput);
  };

  const handleCodeSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (phase.kind !== 'awaitingCode') return;
    const normalized = normalizeCode(codeInput);
    dispatch({ type: 'submitCode', code: codeInput });
    if (!normalized) return;

    const targetEmail = phase.email;
    const targetPurpose = phase.purpose;

    try {
      const result = await verifyCode(
        config,
        {
          email: targetEmail,
          code: normalized,
          purpose: targetPurpose,
          session: authSessionRef.current,
        },
        fetch,
        () => dispatch({ type: 'signUpConfirmed' }),
      );

      if (result.kind === 'awaitingSignInCode') {
        authSessionRef.current = result.session;
        setCodeInput('');
        dispatch({ type: 'signUpNeedsSignInCode', notice: result.notice });
        return;
      }

      authSessionRef.current = undefined;
      saveSession(config, result.tokens);
      setCodeInput('');
      dispatch({ type: 'verified', user: result.user });

      const verified = await fetchVerifiedUser(result.tokens.idToken);
      if (verified) {
        setServerVerified(true);
        dispatch({
          type: 'sessionUpdated',
          user: {
            sub: verified.sub,
            email: verified.email ?? result.user.email,
          },
        });
      }
    } catch (err) {
      dispatch({ type: 'verifyFailed', message: friendlyAuthError(err) });
    }
  };

  const handleCancel = () => {
    if (phase.kind !== 'awaitingCode') return;
    authSessionRef.current = undefined;
    setCodeInput('');
    dispatch({ type: 'cancel' });
  };

  const handleSignOut = async () => {
    authSessionRef.current = undefined;
    setServerVerified(false);
    setCodeInput('');
    await signOutSession(config);
    dispatch({ type: 'signedOut' });
  };

  return (
    <div className="px-5 pt-6 pb-10">
      <h1 className="heading-page text-center">Account</h1>

      {phase.kind === 'restoring' && (
        <div className="mt-8 min-h-[120px]" aria-busy="true" />
      )}

      {(phase.kind === 'guest' || phase.kind === 'sendingCode') && (
        <div className="mx-auto mt-6 max-w-md">
          <p className="text-center text-[14px] leading-relaxed text-ink-2">
            Sign in with your email address. We&apos;ll send a one-time code — no password
            needed. The same account works in the iOS app.
          </p>

          <form onSubmit={handleEmailSubmit} noValidate className="mt-7 space-y-5">
            <div>
              <label
                htmlFor="account-email"
                className="label-caps mb-2 block text-[9.5px] text-ink-3"
              >
                Email Address
              </label>
              <input
                id="account-email"
                name="email"
                type="email"
                autoComplete="email"
                inputMode="email"
                disabled={phase.kind === 'sendingCode'}
                value={emailInput}
                onChange={(e) => setEmailInput(e.target.value)}
                placeholder="you@example.com"
                className="w-full border-b border-ink bg-transparent pb-2 font-body text-[15px] text-ink outline-none placeholder:text-muted disabled:opacity-60"
              />
            </div>

            {errText && (
              <p role="alert" className="text-[13px] leading-relaxed text-ink">
                {errText}
              </p>
            )}

            <button
              type="submit"
              disabled={phase.kind === 'sendingCode'}
              className="action-button-solid w-full cursor-pointer disabled:cursor-default disabled:opacity-60"
            >
              {phase.kind === 'sendingCode' ? 'Sending Code…' : 'Send Code'}
            </button>
          </form>
        </div>
      )}

      {(phase.kind === 'awaitingCode' || phase.kind === 'verifying' || phase.kind === 'signingIn') && (
        <div className="mx-auto mt-6 max-w-md">
          <div className="rounded-sm border border-hairline bg-fill px-5 py-4 text-center">
            <div className="label-caps text-[9px] text-ink-3">Code Sent To</div>
            <div className="mt-1 font-body text-[15px] text-ink">{phase.email}</div>
          </div>

          <p className="mt-5 text-center text-[13.5px] leading-relaxed text-ink-2">
            {phase.kind === 'awaitingCode' && phase.notice
              ? phase.notice
              : phase.kind === 'awaitingCode' && phase.purpose === 'signUp'
                ? 'Enter the 6-digit code we emailed to confirm your new account.'
                : 'Enter the 8-digit sign-in code from your email.'}
          </p>

          <form onSubmit={handleCodeSubmit} noValidate className="mt-6 space-y-5">
            <div>
              <label
                htmlFor="account-code"
                className="label-caps mb-2 block text-[9.5px] text-ink-3"
              >
                Verification Code
              </label>
              <input
                id="account-code"
                name="code"
                type="text"
                inputMode="numeric"
                autoComplete="one-time-code"
                disabled={phase.kind !== 'awaitingCode'}
                value={codeInput}
                onChange={(e) => setCodeInput(e.target.value)}
                placeholder={
                  phase.kind === 'awaitingCode' && phase.purpose === 'signUp'
                    ? '6-digit code'
                    : '8-digit code'
                }
                className="w-full border-b border-ink bg-transparent pb-2 font-mono text-[18px] tracking-[0.2em] text-ink outline-none placeholder:font-body placeholder:text-[15px] placeholder:tracking-normal placeholder:text-muted disabled:opacity-60"
              />
            </div>

            {errText && (
              <p role="alert" className="text-[13px] leading-relaxed text-ink">
                {errText}
              </p>
            )}

            <button
              type="submit"
              disabled={phase.kind !== 'awaitingCode'}
              className="action-button-solid w-full cursor-pointer disabled:cursor-default disabled:opacity-60"
            >
              {phase.kind === 'verifying'
                ? 'Verifying…'
                : phase.kind === 'signingIn'
                  ? 'Signing In…'
                  : 'Verify Code'}
            </button>
          </form>

          {phase.kind === 'awaitingCode' && (
            <div className="mt-6 flex items-center justify-center gap-6 text-[13px] italic text-ink-2">
              <button
                type="button"
                onClick={() => void handleRequestCode(phase.email)}
                className="dotted-link cursor-pointer bg-transparent text-ink"
              >
                Send a new code
              </button>
              <button
                type="button"
                onClick={handleCancel}
                className="dotted-link cursor-pointer bg-transparent text-ink-2"
              >
                Use a different email
              </button>
            </div>
          )}
        </div>
      )}

      {phase.kind === 'signedIn' && (
        <div className="mx-auto mt-6 max-w-md">
          <div className="rounded-sm border border-hairline bg-fill px-5 py-5 space-y-4">
            <div>
              <div className="label-caps text-[9px] text-ink-3">Signed In As</div>
              <div className="mt-1 font-body text-[15.5px] text-ink" data-testid="account-email">
                {phase.user.email ?? 'Signed-in account'}
              </div>
            </div>

            <div className="border-t border-hairline pt-4">
              <div className="label-caps text-[9px] text-ink-3">Account ID</div>
              <div
                className="mt-1 break-all font-mono text-[12.5px] text-ink-2 select-all"
                data-testid="account-sub"
              >
                {phase.user.sub}
              </div>
            </div>

            {serverVerified && (
              <div className="border-t border-hairline pt-3 text-[12px] italic text-ink-3">
                Verified with your Confessional Christianity account.
              </div>
            )}
          </div>

          <p className="mt-5 text-center text-[13px] italic leading-relaxed text-ink-2">
            This is the same account you use in the Confessional Christianity iOS app.
          </p>

          <div className="mt-6">
            <button
              type="button"
              onClick={() => void handleSignOut()}
              className="action-button w-full cursor-pointer bg-transparent"
            >
              Sign Out
            </button>
          </div>
        </div>
      )}
    </div>
  );
}
