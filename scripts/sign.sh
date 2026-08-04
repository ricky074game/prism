#!/usr/bin/env bash
#
# Sign a Prism .ipa locally, on Linux, without Xcode or a Mac.
#
#   ./scripts/sign.sh                     # newest CI build → Prism-signed.ipa
#   ./scripts/sign.sh path/to/Prism.ipa   # a specific one
#
# CI can do this too — the same certificate is in the repo secrets — but this
# path keeps the private key on your own machine, which matters here: the
# certificate belongs to somebody else's developer team, so if it leaks it
# cannot be rotated.
#
# Expects the signing material outside the working tree (this repo is public):
#   ~/.prism-signing/*.p12
#   ~/.prism-signing/*.mobileprovision
set -euo pipefail

SIGNING_DIR="${PRISM_SIGNING_DIR:-$HOME/.prism-signing}"
OUT="${PRISM_SIGNED_OUT:-Prism-signed.ipa}"
ZSIGN="${ZSIGN:-$(command -v zsign || true)}"

die() { echo "error: $*" >&2; exit 1; }

[ -n "$ZSIGN" ] || die "zsign not found. Build it:
    git clone https://github.com/zhlynn/zsign.git
    cd zsign/build/linux && make
  then re-run with ZSIGN=/path/to/zsign, or put it on PATH.
  (Build from build/linux — there is no top-level CMakeLists.txt.)"

# Prefer the re-encrypted container when it's there.
P12=$(ls "$SIGNING_DIR"/prism-signing.p12 2>/dev/null || ls "$SIGNING_DIR"/*.p12 2>/dev/null | head -1) \
  || die "no .p12 in $SIGNING_DIR"
PROV=$(ls "$SIGNING_DIR"/*.mobileprovision 2>/dev/null | head -1) \
  || die "no .mobileprovision in $SIGNING_DIR"
[ -n "${P12:-}" ] && [ -n "${PROV:-}" ] || die "signing material missing from $SIGNING_DIR"

# Read from a file next to the key rather than baked in here. The container
# was re-encrypted with a long random password because the original was a
# single "1" — GitHub redacts every occurrence of a secret's value in its logs,
# so a one-character secret turns "pkcs12" into "pkcs***2" and "exit 1" into
# "exit ***", and a build failure becomes unreadable.
if [ -n "${PRISM_P12_PASSWORD:-}" ]; then
  PASSWORD="$PRISM_P12_PASSWORD"
elif [ -f "$SIGNING_DIR/p12-password.txt" ]; then
  PASSWORD="$(tr -d '\n' < "$SIGNING_DIR/p12-password.txt")"
else
  die "no password: set PRISM_P12_PASSWORD or write $SIGNING_DIR/p12-password.txt"
fi

IPA="${1:-}"
if [ -z "$IPA" ]; then
  echo "Fetching the newest successful build…"
  RID=$(gh run list --workflow=build.yml --status=success --limit 1 \
          --json databaseId --jq '.[0].databaseId')
  TMP=$(mktemp -d)
  # Pinned to the run: artifact names repeat across runs, and --name alone
  # matches every past copy and unpacks them into each other.
  gh run download "$RID" --name Prism-unsigned-ipa --dir "$TMP"
  IPA=$(find "$TMP" -name '*.ipa' | head -1)
  echo "run $RID → $IPA"
fi
[ -f "$IPA" ] || die "no such .ipa: $IPA"

# The profile's App ID is explicit, so it signs exactly one bundle id. Checking
# here turns a confusing on-device install failure into a message that says
# which two things disagree.
WANT=$(python3 - "$PROV" <<'PY'
import sys, plistlib
raw = open(sys.argv[1], 'rb').read()
s = raw.find(b'<?xml'); e = raw.find(b'</plist>') + 8
p = plistlib.loads(raw[s:e])
print(p['Entitlements']['application-identifier'].split('.', 1)[1])
PY
)
GOT=$(python3 - "$IPA" <<'PY'
import sys, zipfile, plistlib, io
z = zipfile.ZipFile(sys.argv[1])
name = next(n for n in z.namelist() if n.count('/') == 2 and n.endswith('.app/Info.plist'))
print(plistlib.load(io.BytesIO(z.read(name)))['CFBundleIdentifier'])
PY
)
[ "$WANT" = "$GOT" ] || die "profile signs '$WANT' but the ipa is '$GOT'.
  Set PRODUCT_BUNDLE_IDENTIFIER in project.yml to '$WANT'."

echo "bundle id : $GOT"
"$ZSIGN" -f -k "$P12" -p "$PASSWORD" -m "$PROV" -o "$OUT" "$IPA"

echo
echo "Signed → $OUT"
python3 - "$OUT" <<'PY'
import sys, zipfile, plistlib, io
z = zipfile.ZipFile(sys.argv[1])
names = z.namelist()
prov = next((n for n in names if n.endswith('embedded.mobileprovision')), None)
assert prov, "no embedded profile — not signed"
assert any('_CodeSignature' in n for n in names), "no _CodeSignature — not signed"
raw = z.read(prov); s = raw.find(b'<?xml'); e = raw.find(b'</plist>') + 8
p = plistlib.loads(raw[s:e])
print("  app id  :", p['Entitlements']['application-identifier'])
print("  devices :", ", ".join(p.get('ProvisionedDevices') or ["all"]))
print("  expires :", p['ExpirationDate'])
PY
