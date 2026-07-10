'use client';

// Shared signin/signup form in the handoff's form language (mockup 5b):
// tracked-caps labels, bottom-border serif inputs, outline action button.
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { useState } from 'react';

import { useAuth } from '@/context/AuthContext';

export function AuthForm({ mode }: { mode: 'signin' | 'signup' }) {
  const { signIn, signUp, signInWithGoogle } = useAuth();
  const router = useRouter();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [confirm, setConfirm] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);
  const [signedUp, setSignedUp] = useState(false);

  const onSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError(null);
    if (mode === 'signup') {
      if (password !== confirm) {
        setError('Passwords do not match');
        return;
      }
      if (password.length < 6) {
        setError('Password must be at least 6 characters');
        return;
      }
    }
    setSubmitting(true);
    try {
      if (mode === 'signin') {
        await signIn(email, password);
        router.push('/');
      } else {
        await signUp(email, password);
        setSignedUp(true);
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Something went wrong');
    } finally {
      setSubmitting(false);
    }
  };

  if (signedUp) {
    return (
      <div className="px-9 pt-14 text-center">
        <h1 className="mb-2.5 font-display text-[19px] font-semibold">Check Your Email</h1>
        <p className="text-[13px] italic leading-relaxed text-ink-2">
          We sent a confirmation link to {email}. Follow it, then sign in.
        </p>
      </div>
    );
  }

  return (
    <div className="px-9 pt-12 pb-10">
      <div className="text-center">
        <h1 className="mb-2.5 font-display text-[19px] font-semibold">
          {mode === 'signin' ? 'Welcome Back' : 'Create an Account'}
        </h1>
        <p className="mb-9 text-[13px] italic leading-relaxed text-ink-2">
          {mode === 'signin'
            ? 'Sign in to continue catechizing.'
            : 'An account holds your children’s plans and progress — nothing more.'}
        </p>
      </div>

      <form onSubmit={onSubmit}>
        <div className="mb-7">
          <label htmlFor="email" className="label-caps mb-2 block text-[9.5px] tracking-[0.1em] text-ink-3">
            Email
          </label>
          <input
            id="email"
            type="email"
            required
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            className="w-full border-b border-ink bg-transparent pb-2 font-body text-[17px] italic text-ink outline-none"
          />
        </div>
        <div className="mb-7">
          <label htmlFor="password" className="label-caps mb-2 block text-[9.5px] tracking-[0.1em] text-ink-3">
            Password
          </label>
          <input
            id="password"
            type="password"
            required
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            className="w-full border-b border-ink bg-transparent pb-2 font-body text-[17px] italic text-ink outline-none"
          />
        </div>
        {mode === 'signup' && (
          <div className="mb-7">
            <label htmlFor="confirm" className="label-caps mb-2 block text-[9.5px] tracking-[0.1em] text-ink-3">
              Confirm Password
            </label>
            <input
              id="confirm"
              type="password"
              required
              value={confirm}
              onChange={(e) => setConfirm(e.target.value)}
              className="w-full border-b border-ink bg-transparent pb-2 font-body text-[17px] italic text-ink outline-none"
            />
          </div>
        )}

        {error && (
          <p className="mb-5 text-center text-[12.5px] italic text-ink-2" role="alert">{error}</p>
        )}

        <button type="submit" disabled={submitting} className="action-button w-full cursor-pointer bg-transparent">
          {submitting ? 'One moment…' : mode === 'signin' ? 'Sign In' : 'Create Account'}
        </button>
      </form>

      <button
        type="button"
        onClick={() => signInWithGoogle().catch((err) => setError(err.message))}
        className="action-button mt-4 w-full cursor-pointer bg-transparent text-ink-2"
      >
        Continue with Google
      </button>

      <div className="mt-7 text-center text-[13px] italic text-ink-2">
        {mode === 'signin' ? (
          <>New here? <Link href="/auth/signup" className="dotted-link text-ink">Create an account</Link></>
        ) : (
          <>Already have an account? <Link href="/auth/signin" className="dotted-link text-ink">Sign in</Link></>
        )}
      </div>
    </div>
  );
}
