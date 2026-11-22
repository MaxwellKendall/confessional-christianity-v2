#!/bin/sh
# The side-by-side check for home and navigation (TKL-926): renders a state of
# the approved prototype 390 pt wide and, given a simulator screenshot of the
# same state, pairs them (prototype | simulator).
#
# Usage: ios/scripts/prototype-shots/render.sh <state> <out.png> [simulator.png]
#   <state> is <today|catechism|lordsday|settings|addchild>-<empty|loading|error|full>[-thu|sat|sun][-signed]-<light|dark>
#
# The simulator side, on a fresh install for "empty":
#   xcrun simctl ui <dev> appearance light|dark
#   xcrun simctl launch <dev> com.confessionalchristianity.app -SkipNotificationOffer YES [-SeedChildren "Samuel:9,Thomas:4"]
#   xcrun simctl io <dev> screenshot simulator.png
set -eu
if [ $# -lt 2 ] || [ $# -gt 3 ]; then
  echo "usage: $0 <state> <out.png> [simulator.png]" >&2
  exit 2
fi
here=$(cd "$(dirname "$0")" && pwd)
chrome=${CHROME:-"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"}
state=$1; out=$2; sim=${3:-}
if [ -n "$sim" ] && [ ! -f "$sim" ]; then
  echo "no simulator screenshot at $sim" >&2
  exit 2
fi
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

shoot() { # <page> <width> <height> <scale> <png>
  "$chrome" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor="$4" \
    --allow-file-access-from-files --virtual-time-budget=4000 --window-size="$2,$3" \
    --screenshot="$5" "file://$1" >/dev/null 2>&1
  [ -s "$5" ] || { echo "Chrome wrote no screenshot" >&2; exit 1; }
}

node "$here/page.mjs" "$state" > "$tmp/page.html"
shoot "$tmp/page.html" 390 844 2 "$tmp/prototype.png"

if [ -z "$sim" ]; then
  cp "$tmp/prototype.png" "$out"
else
  cp "$sim" "$tmp/simulator.png"
  cat > "$tmp/pair.html" <<HTML
<!doctype html><meta charset="utf-8">
<body style="margin:0;background:#8a8a8a;font:600 13px -apple-system,sans-serif;color:#fff">
<div style="display:flex;gap:20px;padding:12px 20px;align-items:flex-start">
<div style="width:390px"><p style="margin:0 0 8px">Prototype · $state</p><img src="prototype.png" width="390"></div>
<div style="width:390px"><p style="margin:0 0 8px">Simulator</p><img src="simulator.png" width="390"></div>
</div>
HTML
  shoot "$tmp/pair.html" 840 900 2 "$tmp/pair.png"
  cp "$tmp/pair.png" "$out"
fi
echo "wrote $out"
