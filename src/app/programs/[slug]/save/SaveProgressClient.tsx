'use client';

// The save gate (mockup 7d): reached only when the visitor deliberately taps
// "Save progress" — never by a timer or on Next Question. Framed as keeping
// the child's place, dismissable without losing anything: state lives in
// localStorage, so "Not now, keep going" simply returns to the question.
// Apple sign-in from the mockup is deferred (provider not configured);
// the email path is the existing email+password flow.
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { useEffect, useState } from 'react';

import { useAuth } from '@/context/AuthContext';
import { AuthForm } from '@/components/AuthForm';
import {
  DEFAULT_LEARNER_NAME,
  getLocalLearner,
} from '@/lib/localCatechismProgress';

export function SaveProgressClient({ slug }: { slug: string }) {
  const { user, loading: authLoading } = useAuth();
  const router = useRouter();
  const [learnerName, setLearnerName] = useState<string | null>(null);
  const sessionHref = `/programs/${slug}/session`;

  useEffect(() => {
    const learner = getLocalLearner();
    setLearnerName(learner.name === DEFAULT_LEARNER_NAME ? null : learner.name);
  }, []);

  // Already signed in: nothing to gate — progress is claimed globally.
  useEffect(() => {
    if (!authLoading && user) router.replace(sessionHref);
  }, [authLoading, router, sessionHref, user]);

  if (authLoading || user) {
    return <div className="min-h-64" aria-hidden="true" />;
  }

  const possessive = learnerName ? `${learnerName}’s` : 'Your';

  return (
    <div className="flex min-h-[calc(100dvh-9rem)] flex-col">
      <div className="px-6 pt-5">
        <Link
          href={sessionHref}
          aria-label="Back to the question"
          className="font-display text-[15px] text-ink no-underline"
        >
          ←
        </Link>
      </div>

      <div className="flex-1">
        <AuthForm
          mode="signup"
          title={`Save ${possessive} Progress`}
          intro={`So you can pick up right where ${learnerName ?? 'your child'} left off, on any device.`}
          submitLabel="Save Progress"
          googlePosition="above"
          solidSubmit
        />
      </div>

      <div className="px-6 pb-10 text-center">
        <Link href={sessionHref} className="dotted-link text-[12.5px] italic text-ink-3">
          Not now, keep going
        </Link>
      </div>
    </div>
  );
}
