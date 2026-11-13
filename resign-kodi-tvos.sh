#!/bin/bash
#
# resign-kodi-tvos.sh — re-sign Kodi with a new certificate/profile and install it on the Apple TV.
# Replaces the iOS App Signer + Xcode "Devices" steps. Run it every year when the certificate expires.
#
# Usage:
#   ./resign-kodi-tvos.sh <profile.mobileprovision> [Kodi-unsigned.ipa | kodi.deb] [--device <name|UDID>] [--no-install]
#
# Defaults: input = ~/Desktop/Kodi-unsigned.ipa, else the newest *kodi*.deb in ~/Downloads.
# The signing certificate is picked automatically: the keychain identity whose certificate is in the profile.
# Installing over the existing Kodi (same bundle ID, same team) keeps its settings and add-ons.

set -euo pipefail

die() { echo "ERROR: $*" >&2; exit 1; }

PROFILE="" ; INPUT="" ; DEVICE="" ; INSTALL=1
while [ $# -gt 0 ]; do
    case "$1" in
        --device)     DEVICE="${2:-}"; shift 2 ;;
        --no-install) INSTALL=0; shift ;;
        -h|--help)    sed -n '2,12p' "$0"; exit 0 ;;
        *.mobileprovision) PROFILE="$1"; shift ;;
        *.ipa|*.deb)  INPUT="$1"; shift ;;
        *) die "unknown argument: $1" ;;
    esac
done

[ -n "$PROFILE" ] || die "pass the .mobileprovision you downloaded (e.g. ~/Downloads/Kodi_AdHoc.mobileprovision)"
[ -f "$PROFILE" ] || die "profile not found: $PROFILE"
command -v python3 >/dev/null || die "python3 not found (install Xcode command line tools)"

if [ -z "$INPUT" ]; then
    if [ -f "$HOME/Desktop/Kodi-unsigned.ipa" ]; then
        INPUT="$HOME/Desktop/Kodi-unsigned.ipa"
    else
        INPUT="$(ls -t "$HOME/Downloads/"*kodi*.deb 2>/dev/null | head -1 || true)"
    fi
fi
[ -n "$INPUT" ] && [ -f "$INPUT" ] || die "no Kodi-unsigned.ipa on Desktop and no *kodi*.deb in Downloads; pass one explicitly"
INPUT="$(cd "$(dirname "$INPUT")" && pwd)/$(basename "$INPUT")"

WORK="$(mktemp -d /tmp/kodi-resign.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
OUT_DIR="$HOME/Desktop"

# --- 1. Read the provisioning profile -------------------------------------------------
security cms -D -i "$PROFILE" > "$WORK/profile.plist" 2>/dev/null || die "could not decode $PROFILE"

python3 - "$WORK" <<'PY'
import plistlib, sys, hashlib, datetime, os
work = sys.argv[1]
p = plistlib.load(open(os.path.join(work, "profile.plist"), "rb"))
ents = p["Entitlements"]
plistlib.dump(ents, open(os.path.join(work, "entitlements.plist"), "wb"))
appid = ents["application-identifier"]
team = p["TeamIdentifier"][0]
bundle = appid.split(".", 1)[1]
shas = [hashlib.sha1(c).hexdigest().upper() for c in p["DeveloperCertificates"]]
exp = p["ExpirationDate"]
plats = ",".join(p.get("Platform", []))
with open(os.path.join(work, "profile.env"), "w") as f:
    f.write(f'PROFILE_NAME="{p["Name"]}"\nTEAM="{team}"\nBUNDLE="{bundle}"\n')
    f.write(f'EXPIRES="{exp:%Y-%m-%d}"\nPLATFORMS="{plats}"\nCERT_SHAS="{" ".join(shas)}"\n')
    f.write(f'EXPIRED={1 if exp < datetime.datetime.now() else 0}\n')
PY
# shellcheck disable=SC1091
. "$WORK/profile.env"

echo "Profile : $PROFILE_NAME (team $TEAM, platform $PLATFORMS)"
echo "App ID  : $BUNDLE"
echo "Expires : $EXPIRES"
[ "$EXPIRED" = 0 ] || die "this profile has already expired; download the new one from developer.apple.com"
case "$PLATFORMS" in *tvOS*) ;; *) echo "WARNING: profile platform is '$PLATFORMS', expected tvOS" ;; esac

# --- 2. Find the signing identity that matches the profile ----------------------------
IDENTITY=""
while read -r sha name; do
    for want in $CERT_SHAS; do
        [ "$sha" = "$want" ] && { IDENTITY="$sha"; ID_NAME="$name"; }
    done
done < <(security find-identity -v -p codesigning | sed -nE 's/^ *[0-9]+\) ([0-9A-F]{40}) (.*)$/\1 \2/p')
[ -n "$IDENTITY" ] || die "none of the profile's certificates is in your keychain with its private key.
       Install the new Apple Distribution certificate (double-click the .cer) on THIS Mac,
       and make sure the profile was generated with that certificate."
echo "Signing : $ID_NAME"

# --- 3. Unpack Kodi.app ---------------------------------------------------------------
echo "Unpacking $(basename "$INPUT")..."
case "$INPUT" in
    *.ipa) unzip -q "$INPUT" -d "$WORK/ipa" ;;
    *.deb) mkdir -p "$WORK/deb"
           if command -v dpkg-deb >/dev/null; then
               dpkg-deb -R "$INPUT" "$WORK/deb"
           else   # a .deb is an ar archive holding data.tar.*; macOS ar + tar can unpack it
               ( cd "$WORK/deb" && ar -x "$INPUT" && tar -xf data.tar.* ) || die "could not unpack $INPUT"
           fi
           mkdir -p "$WORK/ipa/Payload"
           cp -R "$WORK/deb/Applications/"*.app "$WORK/ipa/Payload/" ;;
esac
APP="$(ls -d "$WORK/ipa/Payload/"*.app | head -1)"
[ -d "$APP" ] || die "no .app inside $INPUT"

rm -rf "$APP/PlugIns"                                   # appex bundle IDs would not match the profile
find "$APP" -name _CodeSignature -type d -prune -exec rm -rf {} +
cp "$PROFILE" "$APP/embedded.mobileprovision"

case "$BUNDLE" in
    *\*) echo "Wildcard App ID: keeping the app's own bundle ID" ;;
    *)   /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE" "$APP/Info.plist" ;;
esac

# --- 4. Sign: nested code first (deepest paths first), then the app with entitlements ---
echo "Signing nested frameworks and libraries..."
find "$APP" \( -name '*.framework' -o -name '*.dylib' -o -name '*.so' \) -print \
  | awk '{ print length, $0 }' | sort -rn | cut -d' ' -f2- \
  | while IFS= read -r item; do
        codesign -f -s "$IDENTITY" --timestamp=none "$item" >/dev/null 2>&1 \
          || die "failed to sign $item"
    done

echo "Signing $(basename "$APP")..."
codesign -f -s "$IDENTITY" --timestamp=none --entitlements "$WORK/entitlements.plist" "$APP"
codesign --verify --deep --strict "$APP" || die "signature verification failed"
echo "✓ Signature verified"

# --- 5. Save the signed IPA -----------------------------------------------------------
( cd "$WORK/ipa" && rm -f "$OUT_DIR/Kodi-signed.ipa" && zip -qry "$OUT_DIR/Kodi-signed.ipa" Payload )
echo "✓ Saved $OUT_DIR/Kodi-signed.ipa"

[ "$INSTALL" = 1 ] || exit 0

# --- 6. Install over the existing Kodi on the Apple TV --------------------------------
echo ""
echo "Looking for the Apple TV (wake it up and leave it on the home screen)..."
xcrun devicectl list devices --json-output "$WORK/devices.json" >/dev/null 2>&1 \
  || die "xcrun devicectl failed; open Xcode once so it finishes installing its components"

if [ -z "$DEVICE" ]; then
    DEVICE="$(python3 - "$WORK/devices.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))["result"]["devices"]
tv = [x for x in d if x.get("hardwareProperties", {}).get("platform") == "tvOS"]
if len(tv) == 1:
    print(tv[0]["identifier"])
elif tv:
    for x in tv:
        print("#", x["deviceProperties"]["name"], x["identifier"], file=sys.stderr)
PY
)"
    [ -n "$DEVICE" ] || die "found zero or several Apple TVs; rerun with --device <name or identifier>
       (list them with: xcrun devicectl list devices)"
fi

echo "Installing on $DEVICE..."
xcrun devicectl device install app --device "$DEVICE" "$APP"
echo ""
echo "✓ Done. Kodi is signed until $EXPIRES; re-run this script with the new profile before then."
