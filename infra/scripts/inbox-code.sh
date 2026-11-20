#!/usr/bin/env bash
# Prints the newest code (6 digits for sign-up, 8 for EMAIL_OTP sign-in) mailed to the dev test inbox (ConfessionalChristianityMail-dev) after a
# given time. Usage: AWS_PROFILE=aicoach-dev scripts/inbox-code.sh <since-epoch-seconds> [timeout-seconds]
set -euo pipefail
since=$1; timeout=${2:-90}
bucket=$(aws cloudformation describe-stacks --region us-east-1 --stack-name ConfessionalChristianityMail-dev \
  --query "Stacks[0].Outputs[?OutputKey=='InboxBucket'].OutputValue" --output text)
deadline=$(( $(date +%s) + timeout ))
while [ "$(date +%s)" -lt "$deadline" ]; do
  key=$(aws s3api list-objects-v2 --region us-east-1 --bucket "$bucket" --prefix inbox/ \
    --query "reverse(sort_by(Contents[?LastModified>='$(date -u -r "$since" +%Y-%m-%dT%H:%M:%S)'], &LastModified))[0].Key" --output text 2>/dev/null || true)
  if [ -n "$key" ] && [ "$key" != "None" ]; then
    aws s3 cp --region us-east-1 "s3://$bucket/$key" - | grep -Eo 'code is [0-9]{6,8}' | grep -Eo '[0-9]+' | tail -1
    exit 0
  fi
  sleep 3
done
echo "no mail in s3://$bucket/inbox/ since $since" >&2; exit 1
