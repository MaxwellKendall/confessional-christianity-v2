'use client';

// UI-less: watches for a signed-in user on a device holding guest progress
// and claims it (PRD "Conversion"). Mounted globally so every way a session
// can appear — password sign-in, the Google OAuth redirect, a
// confirm-email-then-sign-in-later — triggers the claim, not just the save
// gate's happy path. Errors leave the local store intact; the next auth
// event retries.
import { useEffect, useRef } from 'react';

import { useAuth } from '@/context/AuthContext';
import { claimLocalProgress, LOCAL_PROGRESS_CLAIMED_EVENT } from '@/lib/claimLocalProgress';
import { getLocalProgressSnapshot } from '@/lib/localCatechismProgress';
import { getSupabaseBrowserClient } from '@/lib/supabase/client';

export function LocalProgressMigrator() {
  const { user } = useAuth();
  const supabase = getSupabaseBrowserClient();
  const inFlight = useRef(false);

  useEffect(() => {
    if (!user || !supabase || inFlight.current) return;
    if (!getLocalProgressSnapshot().track) return;
    inFlight.current = true;
    claimLocalProgress(supabase, user.id)
      .then((result) => {
        if (result !== 'nothing-to-claim') {
          // children lists fetched before the claim landed need to know
          window.dispatchEvent(new Event(LOCAL_PROGRESS_CLAIMED_EVENT));
        }
      })
      .catch((error) => {
        console.error('Claiming local progress failed; will retry on next sign-in', error);
      })
      .finally(() => {
        inFlight.current = false;
      });
  }, [supabase, user]);

  return null;
}
