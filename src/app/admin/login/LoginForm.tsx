'use client';

import { useActionState } from 'react';

import { login, type LoginState } from '../actions';

export function LoginForm({ next }: { next: string }) {
  const [state, action, pending] = useActionState<LoginState, FormData>(login, { error: null });
  return (
    <form action={action} className="flex flex-col gap-3 text-left">
      <input type="hidden" name="next" value={next} />
      <label className="label-caps text-ink-3" htmlFor="admin-password">Password</label>
      <input
        id="admin-password"
        name="password"
        type="password"
        autoComplete="current-password"
        required
        className="rounded-md border border-hairline bg-white px-3 py-2 font-body text-[15px]"
      />
      {state.error && <p className="m-0 text-[13px] text-red-800" role="alert">{state.error}</p>}
      <button
        type="submit"
        disabled={pending}
        className="mt-2 rounded-md bg-ink px-4 py-2.5 label-caps text-[11px] text-card disabled:opacity-50"
      >
        {pending ? 'Signing in…' : 'Sign in'}
      </button>
    </form>
  );
}
