// Pure sign-in state machine for /account (TKL-1043), mirroring
// ios/DomainKit/Sources/DomainKit/Auth.swift so web and iOS behave identically.

export type CodePurpose = 'signIn' | 'signUp';

export interface AccountUser {
  sub: string;
  email: string | null;
}

export type AccountPhase =
  | { kind: 'restoring' }
  | { kind: 'guest' }
  | { kind: 'sendingCode'; email: string }
  | { kind: 'awaitingCode'; email: string; purpose: CodePurpose; notice?: string }
  | { kind: 'verifying'; email: string; code: string; purpose: CodePurpose }
  | { kind: 'signingIn'; email: string }
  | { kind: 'signedIn'; user: AccountUser };

export type AccountError =
  | { kind: 'invalidEmail' }
  | { kind: 'invalidCode' }
  | { kind: 'sendFailed'; message: string }
  | { kind: 'verifyFailed'; message: string };

export interface AccountState {
  phase: AccountPhase;
  error: AccountError | null;
}

export type AccountEvent =
  | { type: 'restored'; user: AccountUser | null }
  | { type: 'requestCode'; email: string }
  | { type: 'codeSent' }
  | { type: 'signUpCodeSent' }
  | { type: 'sendFailed'; message: string }
  | { type: 'submitCode'; code: string }
  | { type: 'signUpConfirmed' }
  | { type: 'signUpNeedsSignInCode'; notice: string }
  | { type: 'verified'; user: AccountUser }
  | { type: 'verifyFailed'; message: string }
  | { type: 'cancel' }
  | { type: 'signedOut' }
  | { type: 'sessionEnded' }
  | { type: 'sessionUpdated'; user: AccountUser };

export const initialAccountState: AccountState = {
  phase: { kind: 'restoring' },
  error: null,
};

/**
 * Trimmed, lowercased email address if it looks deliverable, else null.
 * Deliberately modest: one "@", a non-empty local part without whitespace,
 * and a dotted domain with no empty labels. Cognito does the real check.
 */
export const normalizeEmail = (raw: string): string | null => {
  const email = raw.trim().toLowerCase();
  if (!email || /\s/.test(email)) return null;
  const parts = email.split('@');
  if (parts.length !== 2 || !parts[0]) return null;
  const labels = parts[1].split('.');
  if (labels.length < 2 || labels.some((label) => !label)) return null;
  return email;
};

/**
 * Strips spaces and dashes and accepts 6-digit (sign-up) or 8-digit (EMAIL_OTP)
 * ASCII codes only.
 */
export const normalizeCode = (raw: string): string | null => {
  const code = raw.replace(/[\s-]+/g, '');
  if (!/^(?:\d{6}|\d{8})$/.test(code)) return null;
  return code;
};

export const accountReducer = (state: AccountState, event: AccountEvent): AccountState => {
  const { phase } = state;

  switch (event.type) {
    case 'restored': {
      if (phase.kind !== 'restoring') return state;
      return {
        phase: event.user ? { kind: 'signedIn', user: event.user } : { kind: 'guest' },
        error: null,
      };
    }

    case 'requestCode': {
      if (phase.kind !== 'guest' && phase.kind !== 'awaitingCode') return state;
      const email = normalizeEmail(event.email);
      if (!email) {
        return { phase, error: { kind: 'invalidEmail' } };
      }
      return { phase: { kind: 'sendingCode', email }, error: null };
    }

    case 'codeSent': {
      if (phase.kind !== 'sendingCode') return state;
      return {
        phase: { kind: 'awaitingCode', email: phase.email, purpose: 'signIn' },
        error: null,
      };
    }

    case 'signUpCodeSent': {
      if (phase.kind !== 'sendingCode') return state;
      return {
        phase: { kind: 'awaitingCode', email: phase.email, purpose: 'signUp' },
        error: null,
      };
    }

    case 'sendFailed': {
      if (phase.kind !== 'sendingCode') return state;
      return {
        phase: { kind: 'guest' },
        error: { kind: 'sendFailed', message: event.message },
      };
    }

    case 'submitCode': {
      if (phase.kind !== 'awaitingCode') return state;
      const code = normalizeCode(event.code);
      if (!code) {
        return { phase, error: { kind: 'invalidCode' } };
      }
      return {
        phase: { kind: 'verifying', email: phase.email, code, purpose: phase.purpose },
        error: null,
      };
    }

    case 'signUpConfirmed': {
      if (phase.kind !== 'verifying' || phase.purpose !== 'signUp') return state;
      return {
        phase: { kind: 'signingIn', email: phase.email },
        error: null,
      };
    }

    case 'signUpNeedsSignInCode': {
      if (phase.kind !== 'signingIn' && !(phase.kind === 'verifying' && phase.purpose === 'signUp')) {
        return state;
      }
      return {
        phase: {
          kind: 'awaitingCode',
          email: phase.email,
          purpose: 'signIn',
          notice: event.notice,
        },
        error: null,
      };
    }

    case 'verified': {
      if (phase.kind !== 'verifying' && phase.kind !== 'signingIn') return state;
      return {
        phase: { kind: 'signedIn', user: event.user },
        error: null,
      };
    }

    case 'verifyFailed': {
      if (phase.kind === 'verifying') {
        return {
          phase: { kind: 'awaitingCode', email: phase.email, purpose: phase.purpose },
          error: { kind: 'verifyFailed', message: event.message },
        };
      }
      if (phase.kind === 'signingIn') {
        return {
          phase: { kind: 'guest' },
          error: { kind: 'verifyFailed', message: event.message },
        };
      }
      return state;
    }

    case 'cancel': {
      if (phase.kind !== 'awaitingCode') return state;
      return { phase: { kind: 'guest' }, error: null };
    }

    case 'signedOut':
    case 'sessionEnded': {
      if (phase.kind !== 'signedIn') return state;
      return { phase: { kind: 'guest' }, error: null };
    }

    case 'sessionUpdated': {
      return { phase: { kind: 'signedIn', user: event.user }, error: null };
    }
  }
};
