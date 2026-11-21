#!/usr/bin/env bash
# Dev only. Behavioral check that a password can't be used to sign in (TKL-850).
# Plays an attacker: signs up a fresh address at the dev test inbox WITH a password, confirms it with the
# emailed code, then tries USER_AUTH with PREFERRED_CHALLENGE=PASSWORD (and SELECT_CHALLENGE → PASSWORD), and
# finally checks the emailed-code sign-in still works for that user. Deletes the user at the end.
# Exit 0 = passwords rejected and EMAIL_OTP works. Exit 1 = a password got tokens (or EMAIL_OTP broke).
# Usage: AWS_PROFILE=aicoach-dev scripts/password-probe.sh
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
region=us-east-1
out() { aws cloudformation describe-stacks --region $region --stack-name ConfessionalChristianity-dev \
  --query "Stacks[0].Outputs[?OutputKey=='$1'].OutputValue" --output text; }
pool=$(out UserPoolId); client=$(out AppClientId)
user="pw-probe-$(date +%s)@cc-dev-mail.barbrabell.com"
pw="Probe-$(openssl rand -hex 12)-A1!"
cleanup() { aws cognito-idp admin-delete-user --region $region --user-pool-id "$pool" --username "$user" >/dev/null 2>&1 || true; }
trap cleanup EXIT
fail=0

since=$(date +%s)
aws cognito-idp sign-up --region $region --client-id "$client" --username "$user" --password "$pw" \
  --user-attributes Name=email,Value="$user" --query UserConfirmed --output text || { echo "sign-up failed"; exit 1; }
code=$("$here/inbox-code.sh" "$since") || { echo "no sign-up code arrived"; exit 1; }
aws cognito-idp confirm-sign-up --region $region --client-id "$client" --username "$user" --confirmation-code "$code" \
  && echo "confirmed $user" || { echo "confirm failed"; exit 1; }

# 1. USER_AUTH, asking for PASSWORD directly.
r=$(aws cognito-idp initiate-auth --region $region --client-id "$client" --auth-flow USER_AUTH \
  --auth-parameters USERNAME="$user",PREFERRED_CHALLENGE=PASSWORD,PASSWORD="$pw" 2>&1)
if echo "$r" | grep -q AccessToken; then echo "FAIL: USER_AUTH + PASSWORD returned tokens"; fail=1
else echo "ok: USER_AUTH + PASSWORD refused: $(echo "$r" | grep -Eo '[A-Za-z]+Exception[^.]*' | head -1)"; fi

# 2. USER_AUTH without a preference, then answer SELECT_CHALLENGE with PASSWORD.
r=$(aws cognito-idp initiate-auth --region $region --client-id "$client" --auth-flow USER_AUTH \
  --auth-parameters USERNAME="$user" --output json 2>&1)
session=$(echo "$r" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("Session",""))' 2>/dev/null)
challenge=$(echo "$r" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("ChallengeName",""))' 2>/dev/null)
echo "unpreferred USER_AUTH → ${challenge:-error}"
if [ "$challenge" = "SELECT_CHALLENGE" ]; then
  r=$(aws cognito-idp respond-to-auth-challenge --region $region --client-id "$client" --challenge-name SELECT_CHALLENGE \
    --session "$session" --challenge-responses USERNAME="$user",ANSWER=PASSWORD,PASSWORD="$pw" 2>&1)
  if echo "$r" | grep -q AccessToken; then echo "FAIL: SELECT_CHALLENGE → PASSWORD returned tokens"; fail=1
  else echo "ok: SELECT_CHALLENGE → PASSWORD refused: $(echo "$r" | grep -Eo '[A-Za-z]+Exception[^.]*' | head -1)"; fi
fi

# 3. The emailed code still signs the same user in.
since=$(date +%s)
r=$(aws cognito-idp initiate-auth --region $region --client-id "$client" --auth-flow USER_AUTH \
  --auth-parameters USERNAME="$user",PREFERRED_CHALLENGE=EMAIL_OTP --output json 2>&1)
session=$(echo "$r" | python3 -c 'import json,sys; print(json.load(sys.stdin)["Session"])' 2>/dev/null) || { echo "FAIL: no EMAIL_OTP challenge: $r"; exit 1; }
sleep 2
code=$("$here/inbox-code.sh" "$since") || { echo "FAIL: no sign-in code arrived"; exit 1; }
r=$(aws cognito-idp respond-to-auth-challenge --region $region --client-id "$client" --challenge-name EMAIL_OTP \
  --session "$session" --challenge-responses USERNAME="$user",EMAIL_OTP_CODE="$code" 2>&1)
if echo "$r" | grep -q AccessToken; then echo "ok: EMAIL_OTP (${#code}-digit code) returned tokens"
else echo "FAIL: EMAIL_OTP answer refused: $r"; fail=1; fi

[ $fail = 0 ] && echo PASS || echo FAIL
exit $fail
