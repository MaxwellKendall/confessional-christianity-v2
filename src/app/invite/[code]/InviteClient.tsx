'use client';

import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { useState } from 'react';

import { useAuth } from '@/context/AuthContext';
import { useShareInvite } from '@/hooks/useShareInvite';

export function InviteClient({ code }: { code: string }) {
  const { user, loading: authLoading } = useAuth();
  const { invite, loading, error, accepting, acceptInvite } = useShareInvite(code);
  const router = useRouter();
  const [acceptError, setAcceptError] = useState<string | null>(null);

  if (loading || authLoading) {
    return <p className="px-8 pt-14 text-center text-[13px] italic text-ink-2">One moment…</p>;
  }

  if (error || !invite) {
    return (
      <div className="px-9 pt-14 text-center">
        <h1 className="mb-2.5 font-display text-[19px] font-semibold">Invite Not Available</h1>
        <p className="text-[13px] italic leading-relaxed text-ink-2">{error ?? 'Invite not found.'}</p>
      </div>
    );
  }

  return (
    <div className="px-9 pt-14 text-center">
      <div className="label-caps mb-3 text-[9.5px] text-ink-3">Shared Plan</div>
      <h1 className="mb-2.5 font-display text-[19px] font-semibold">
        Join {invite.child?.name ?? 'this child'}’s Guardians
      </h1>
      <p className="mb-9 text-[13px] italic leading-relaxed text-ink-2">
        You’ve been invited to follow along and help catechize
        {invite.child?.name ? ` ${invite.child.name}` : ''}.
      </p>

      {user ? (
        <>
          <button
            type="button"
            disabled={accepting}
            onClick={async () => {
              setAcceptError(null);
              try {
                await acceptInvite();
                router.push('/');
              } catch (err) {
                setAcceptError(err instanceof Error ? err.message : 'Failed to accept invite');
              }
            }}
            className="action-button w-full cursor-pointer bg-transparent"
          >
            {accepting ? 'Joining…' : 'Accept Invite'}
          </button>
          {acceptError && (
            <p className="mt-4 text-[12.5px] italic text-ink-2" role="alert">{acceptError}</p>
          )}
        </>
      ) : (
        <p className="text-[13px] italic text-ink-2">
          <Link href="/auth/signin" className="dotted-link text-ink">Sign in</Link>
          {' '}or{' '}
          <Link href="/auth/signup" className="dotted-link text-ink">create an account</Link>
          {' '}to accept.
        </p>
      )}
    </div>
  );
}
