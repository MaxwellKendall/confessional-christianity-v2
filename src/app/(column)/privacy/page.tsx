import type { Metadata } from 'next';

import { Markdown } from '@/components/Markdown';

export const metadata: Metadata = {
  title: 'Privacy Policy',
  description: 'How Confessional Christianity handles data: no tracking, optional email sign-in, sermon-note drafting, and a few anonymous counts.',
  alternates: { canonical: '/privacy' },
};

const body = `
Confessional Christianity — on the web and in the iOS app — does not track
you and does not sell or share your information. You can use it without an
account. If you choose to sign in, the iOS app keeps your email address and
what you've saved with your account, as described below. The iOS app also
counts a few anonymous events.

## What we don't do

Nothing is used to track you across other companies' apps or websites, and
nothing is shared with data brokers or advertisers. We don't use cookies to
identify or follow you across visits.

## Where your progress is stored

Without an account, your place in a catechism — which question you're on,
which milestones you've reached — is saved only on your own device:

- On the web, in your browser's local storage.
- In the iOS app, in a local, on-device store, shared only with the app's
  own Home Screen widget so it can show your current question.

This data doesn't leave your device and we have no access to it. Clearing
your browser data, or deleting the app, deletes it permanently.

## Accounts (iOS, optional)

Signing in is optional; it lets your family's data follow you to another
iPhone and be restored if you reinstall the app.

- **Your email address.** You sign in with your email address. There is no
  password: each time, we email you a one-time sign-in code, and the code
  only lets you into the account it was sent for. Your email address is
  used only to sign you in and to send those codes.
- **What syncs.** While you're signed in, the app saves with your account
  the children you add (your children's names and ages), their catechism
  progress (the catechism, the current question and milestones), and your
  Lord's Day sermon notes and cards (the text drafted from your notes, the
  cards you keep, and the sermon's passage, title and preacher if you enter
  them).
- **Where it's kept.** Account data is stored with Amazon Web Services, our
  hosting provider, and is used only to run the app for you. It isn't used
  for advertising or shared with anyone else.

Signing out stops syncing; what's already on your iPhone stays there. To
have your account and everything saved with it deleted, email us at the
address below.

## Drafting cards from sermon-note photos (iOS)

When you photograph your sermon notes (or type them) and ask the app to
draft the week's cards, the photos or text are sent to our server and on to
Google Gemini, Google's AI service, only to draft the cards. Your photos are
not stored online: our server doesn't keep them, and the originals stay on
your iPhone. The drafted text and cards are stored with your account when
you're signed in, and only on your iPhone otherwise. We use Google's paid
API service, whose terms don't allow Google to use these requests to train
its models.

## Third-party services we use

Two other features call external services to do their job — neither
receives anything that identifies you:

- **Scripture text.** Bible passages are fetched from the ESV API
  (Crossway) by reference (e.g. "John 4:24") to display alongside
  catechism questions and library entries. Most passages are bundled with
  the iOS app itself, so this call is only needed for the rest.
- **Search.** Searching the confession/catechism library sends your search
  text to Algolia, a search service, using a key restricted to read-only
  search queries. No account or personal data is attached to these
  requests.

## Anonymous usage counts (iOS)

To learn whether the Lord's Day cards help people through the week, the iOS
app sends three anonymous counts to PostHog, an analytics service:

- **A sermon kept:** when you add a sermon's cards to your week, with the
  number of cards.
- **A day opened:** at most once a day, when the week's cards are on screen.
- **A card shared:** when you open the share sheet on a card, with the card's
  kind (key point, quote or verse).

Each count carries a random number made when the app was installed, so
counts from the same install can be told apart. It isn't linked to your
name, an account or your device's advertising identifier, and deleting the
app discards it. **Your notes, your cards' words, your photos, Bible
references, the preacher, your church and your email are never sent.**
PostHog's person profiles and location lookup are turned off for these
counts. Like any web request, the connection itself reveals your IP address
to PostHog; we don't use it.

## Notifications (iOS)

If you turn on daily practice reminders in the iOS app, the reminder is
scheduled locally on your device using Apple's notification system. No
reminder data is sent anywhere.

## Children's privacy

This app is designed for parents to use with their children. Accounts are
for adults: only the signed-in parent's email address is collected, and a
child's name and age are saved only if the parent adds them, so the app can
keep that child's place in the catechism. The anonymous counts above say
nothing about who is using the app.

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
