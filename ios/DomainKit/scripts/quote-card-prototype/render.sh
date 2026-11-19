#!/bin/sh
# Regenerates the prototype reference PNGs (format x palette) that
# QuoteCardSnapshotTests compares the native renderer against.
# Usage: ios/DomainKit/scripts/quote-card-prototype/render.sh
set -eu
here=$(cd "$(dirname "$0")" && pwd)
out="$here/../../Tests/DomainKitTests/Fixtures/QuoteCard/prototype"
chrome=${CHROME:-"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"}
mkdir -p "$out"
for spec in square:1080:1080 story:1080:1920 linkPreview:1200:630; do
  name=${spec%%:*}; rest=${spec#*:}; w=${rest%%:*}; h=${rest#*:}
  fmt=$name; [ "$name" = linkPreview ] && fmt=og
  for p in 0 1 2 3 4 5 6 7 8; do
    "$chrome" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=1 \
      --allow-file-access-from-files --virtual-time-budget=4000 --window-size="$w,$h" \
      --screenshot="$out/$name-$p.png" "file://$here/card.html#$fmt,$p" >/dev/null 2>&1
  done
done
echo "wrote $(ls "$out" | wc -l | tr -d ' ') PNGs to $out"
