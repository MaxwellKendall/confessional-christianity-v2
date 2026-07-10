'use client';

// Typed port of v1's invite-acceptance hook. Acceptance goes through the
// accept_share_invite SECURITY DEFINER function (see the sharing migrations)
// so RLS never recurses.
import { useCallback, useEffect, useState } from 'react';

import { useAuth } from '@/context/AuthContext';
import { getSupabaseBrowserClient } from '@/lib/supabase/client';
import type { ChildShareInviteRow } from '@/lib/database.types';

interface InviteWithChild extends ChildShareInviteRow {
  child: { id: string; name: string } | null;
}

export const useShareInvite = (inviteCode: string) => {
  const [invite, setInvite] = useState<InviteWithChild | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [accepting, setAccepting] = useState(false);
  const { user } = useAuth();
  const supabase = getSupabaseBrowserClient();

  const fetchInvite = useCallback(async () => {
    if (!inviteCode || !supabase) {
      setInvite(null);
      setLoading(false);
      return;
    }

    try {
      setLoading(true);
      const { data, error: fetchError } = await supabase
        .from('child_share_invites')
        .select('*, child:children (id, name)')
        .eq('invite_code', inviteCode)
        .single();

      if (fetchError) throw fetchError;

      const row = data as unknown as InviteWithChild;
      if (row && new Date(row.expires_at) < new Date()) {
        setError('This invite has expired');
        setInvite(null);
      } else if (row?.accepted_at) {
        setError('This invite has already been used');
        setInvite(null);
      } else {
        setInvite(row);
        setError(null);
      }
    } catch {
      setError('Invite not found');
    } finally {
      setLoading(false);
    }
  }, [inviteCode, supabase]);

  useEffect(() => {
    fetchInvite();
  }, [fetchInvite]);

  const acceptInvite = async () => {
    if (!user || !supabase) throw new Error('Must be logged in');
    if (!invite) throw new Error('No valid invite');

    setAccepting(true);
    try {
      const { data, error: rpcError } = await supabase
        .rpc('accept_share_invite', { p_invite_code: inviteCode });
      if (rpcError) throw rpcError;
      const result = data as { success?: boolean; error?: string } | null;
      if (!result?.success) throw new Error(result?.error || 'Failed to accept invite');
      return result;
    } finally {
      setAccepting(false);
    }
  };

  return {
    invite,
    loading,
    error,
    accepting,
    acceptInvite,
  };
};
