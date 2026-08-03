import type { Metadata } from 'next';

import { Markdown } from '@/components/Markdown';

export const metadata: Metadata = {
  title: 'Privacy Policy',
  description: 'How Confessional Christianity handles data — in short, it doesn\'t collect any.',
  alternates: { canonical: '/privacy' },
};

const body = `
Confessional Christianity — on the web and in the iOS app — does not require
an account and does not collect personal information.

## What we don't collect

There are no user accounts, no names, no email addresses, and no analytics
or tracking of any kind. We don't use cookies to identify or follow you
across visits.

## Where your progress is stored

Your place in a catechism — which question you're on, which milestones
you've reached — is saved only on your own device:

- On the web, in your browser's local storage.
- In the iOS app, in a local, on-device store, shared only with the app's
  own Home Screen widget so it can show your current question.

This data never leaves your device and we have no access to it. Clearing
your browser data, or deleting the app, deletes it permanently.

## Third-party services we use

A couple of features call external services to do their job — neither
receives anything that identifies you:

- **Scripture text.** Bible passages are fetched from the ESV API
  (Crossway) by reference (e.g. "John 4:24") to display alongside
  catechism questions and library entries. Most passages are bundled with
  the iOS app itself, so this call is only needed for the rest.
- **Search.** Searching the confession/catechism library sends your search
  text to Algolia, a search service, using a key restricted to read-only
  search queries. No account or personal data is attached to these
  requests.

## Notifications (iOS)

If you turn on daily practice reminders in the iOS app, the reminder is
scheduled locally on your device using Apple's notification system. No
reminder data is sent anywhere.

## Children's privacy

This app is designed for families to use together to catechize children,
and by design collects no information from anyone, child or adult.

## Changes to this policy

If this policy changes, the update will be posted on this page.

## Contact

Questions about this policy can be sent to
[maxwell.n.kendall@gmail.com](mailto:maxwell.n.kendall@gmail.com).
`;

export default function PrivacyPage() {
  return (
    <article className="px-5 pb-6 pt-6">
      <h1 className="mb-6 text-center heading-page">Privacy Policy</h1>
      <Markdown source={body} />
    </article>
  );
}
