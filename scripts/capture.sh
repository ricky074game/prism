#!/usr/bin/env bash
#
# Boots one simulator and captures every screen into a directory.
#
#   ./scripts/capture.sh "iPhone 16 Pro" shots
#   ./scripts/capture.sh "iPad Pro 13-inch (M4)" shots-ipad
#
# Shared by both passes so the two device families can never drift into
# capturing different screens — which is exactly how an iPad regression stays
# invisible while the phone shots look fine.
set -euo pipefail

DEVICE="$1"
OUT="$2"
BUNDLE="com.prism.client"

APP=$(find build/Build/Products -name "Prism.app" -maxdepth 3 | head -1)
echo "app: $APP"

RUNTIME=$(xcrun simctl list runtimes --json | python3 -c "
import json,sys
rs=[r for r in json.load(sys.stdin)['runtimes'] if r['isAvailable'] and 'iOS' in r['name']]
print(sorted(rs, key=lambda r: r['version'])[-1]['identifier'])
")
echo "runtime: $RUNTIME"

# The exact iPad model names change with every Xcode release, so an exact match
# is tried first and then anything of the same family. A hard-coded name that
# silently stops existing would skip the whole pass.
DEVICE_TYPE=$(xcrun simctl list devicetypes --json | python3 -c "
import json,sys
want='''$DEVICE'''
ts=json.load(sys.stdin)['devicetypes']
exact=[t for t in ts if t['name']==want]
if exact:
    print(exact[0]['identifier']); raise SystemExit
family='iPad' if 'iPad' in want else 'iPhone'
same=[t for t in ts if family in t['name'] and 'Pro' in t['name']]
if not same:
    same=[t for t in ts if family in t['name']]
print(sorted(same, key=lambda t: t['name'])[-1]['identifier'])
")
echo "device type: $DEVICE_TYPE"

UDID=$(xcrun simctl create "prism-shots-$$" "$DEVICE_TYPE" "$RUNTIME")
trap 'xcrun simctl shutdown "$UDID" >/dev/null 2>&1 || true; xcrun simctl delete "$UDID" >/dev/null 2>&1 || true' EXIT

xcrun simctl boot "$UDID"
xcrun simctl bootstatus "$UDID" -b

# Dark status bar values so the captures look deliberate.
xcrun simctl status_bar "$UDID" override \
  --time "9:41" --batteryState charged --batteryLevel 100 \
  --cellularMode active --cellularBars 4 --wifiMode active --wifiBars 3 || true

xcrun simctl install "$UDID" "$APP"

mkdir -p "$OUT"

shoot () {
  local screen="$1"; local name="$2"; local wait="${3:-6}"
  echo "--- $name"
  xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
  sleep 1
  # Launch arguments put the app straight onto the target screen with fixture
  # data, so each capture is one deterministic launch.
  xcrun simctl launch "$UDID" "$BUNDLE" -prism-demo -prism-screen "$screen" || true
  sleep "$wait"
  xcrun simctl io "$UDID" screenshot --type=png "$OUT/$name.png" || true
}

shoot home           01-home           8
shoot watch          02-watch          10
shoot scrubber       03-scrubber       10
shoot shorts         04-shorts         8
shoot search         05-search         6
shoot settings       06-settings       6
shoot channel        07-channel        8
shoot channel-shorts 08-channel-shorts 8
shoot posts          09-posts          8

echo "--- captured ---"
ls -la "$OUT"
