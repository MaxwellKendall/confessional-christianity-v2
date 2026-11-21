# Confessional Christianity infra (TKL-850)

AWS CDK app for accounts: a Cognito user pool where people sign in with a code emailed to them
(choice-based `USER_AUTH`, `EMAIL_OTP`), after remix's `infra/`. All changes go through CDK; nothing
is created in the console. Account `397614038040` (profile `aicoach-dev`, us-east-1), shared with
ai-coach and remix as separate stacks.

```
bin/app.ts               entry; stage comes from `-c stage=…` (dev | prod), settings from cdk.json
lib/stack.ts             ConfessionalChristianity-{stage}: user pool + public iOS client
lib/mail.ts              ConfessionalChristianityMail-{stage}: the SES domain identity the codes come from
scripts/outputs.ts       writes ../ios/App/Resources/amplify_outputs.{stage}.json, prints the server's settings
scripts/inbox-code.sh    dev only: prints the newest code mailed to the test inbox
scripts/password-probe.sh dev only: live check that passwords can't sign in
lambda/no-password/      PostConfirmation/PreAuthentication trigger that scrambles passwords
test/                    vitest: CDK template assertions
```

## Sign-in rules

- Cognito insists `PASSWORD` stays in the pool's allowed first factors, so "no passwords" is enforced
  three ways: the client allows only `ALLOW_USER_AUTH` and `ALLOW_REFRESH_TOKEN_AUTH` (no SRP, no
  `USER_PASSWORD_AUTH`); account recovery is off, so `ForgotPassword` can't set a password; and the
  `NoPassword` Lambda (`lambda/no-password/`, PostConfirmation + PreAuthentication triggers) replaces any
  password with a random one nobody sees, so a password passed to `SignUp` or `ChangePassword` never
  signs anyone in. If that Lambda fails, the confirmation or sign-in fails too.
- Because every user ends up with a (random) password, `USER_AUTH` without a preference answers
  `SELECT_CHALLENGE`: the app must send `PREFERRED_CHALLENGE=EMAIL_OTP`.
- `AWS_PROFILE=aicoach-dev scripts/password-probe.sh` (dev, live) signs up a test user with a password,
  checks both password paths are refused and the emailed code still works, then deletes the user.
- Sign-up codes are 6 digits; `EMAIL_OTP` sign-in codes are **8 digits** (Cognito's fixed length).
- Sign up: `SignUp` with only the email (no password), then `ConfirmSignUp` with the emailed code.
  Sign in: `InitiateAuth USER_AUTH` with `PREFERRED_CHALLENGE=EMAIL_OTP`, then
  `RespondToAuthChallenge EMAIL_OTP` with `EMAIL_OTP_CODE`.

## Mail

The mail stack is separate because Cognito refuses an unverified SES identity, and DKIM verification
finishes minutes after the identity is created. Deploy it first and wait for
`aws sesv2 get-email-identity --email-identity <domain>` to show `SUCCESS`.

- **dev** sends from `no-reply@cc-dev-mail.barbrabell.com`. `barbrabell.com` is the only Route 53 zone
  in the account, so the stack writes the DKIM and MX records itself. Mail to any address at that
  subdomain lands in the stack's S3 bucket (`InboxBucket` output, 7-day expiry); the test address is
  `otp-test@cc-dev-mail.barbrabell.com`. SES is still in the sandbox, which only allows verified
  recipients: this subdomain is one.
- **prod** sends from `no-reply@confessionalchristianity.com`. That domain's DNS is on Vercel (outside
  AWS), so the stack outputs `DkimRecords` to add there. Real users also need SES production access.

## Commands

```bash
npm test                                                  # unit tests, no AWS needed
npx cdk diff --all --profile aicoach-dev                  # read it before every deploy
npx cdk deploy --all --profile aicoach-dev                # dev (mail stack first)
AWS_PROFILE=aicoach-dev npm run outputs                   # ios/App/Resources/amplify_outputs.dev.json
npx cdk diff --all --profile aicoach-dev -c stage=prod    # prod: read it; stop on any pool replacement
npx cdk deploy --all --profile aicoach-dev -c stage=prod
AWS_PROFILE=aicoach-dev npm run outputs prod
```

Prod's user pool and SES identity are `RETAIN`, and the pool has deletion protection.

## Account sync

See [Account sync](SYNC.md) for the AppSync transport, guardian access and account deletion contract.
