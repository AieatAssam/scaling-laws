#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd)
GODOT=${GODOT:-$(command -v godot || true)}
SDK=${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}

if [[ -z "$GODOT" ]]; then echo "Godot 4.7.2 is required; set GODOT to its executable." >&2; exit 1; fi
if ! command -v java >/dev/null 2>&1; then echo "Java 17 is required; install a JDK and put java on PATH." >&2; exit 1; fi
if ! java -version 2>&1 | head -1 | grep -Eq 'version "17([.]|")'; then echo "Java 17 is required for Godot 4.7 Android exports." >&2; exit 1; fi
if [[ -z "$SDK" || ! -x "$SDK/cmdline-tools/latest/bin/sdkmanager" ]]; then
  echo "Android SDK with cmdline-tools/latest is required; set ANDROID_HOME or ANDROID_SDK_ROOT." >&2; exit 1
fi
if [[ ! -d "$SDK/platforms/android-36" || ! -d "$SDK/build-tools/36.1.0" || ! -d "$SDK/ndk/29.0.14206865" ]]; then
  echo "Install Godot 4.7 Android SDK packages: platform android-36, build-tools 36.1.0, NDK 29.0.14206865, and CMake 3.22.1." >&2
  exit 1
fi
if [[ -z "${KEYSTORE:-}" || -z "${ALIAS:-}" || -z "${PASSWORD:-}" || ! -f "${KEYSTORE:-}" ]]; then
  echo "Set KEYSTORE, ALIAS and PASSWORD (for example by sourcing ~/.keys/scaling-laws/signing.env)." >&2
  exit 1
fi
APKSIGNER="$SDK/build-tools/36.1.0/apksigner"
if [[ ! -x "$APKSIGNER" ]] || ! command -v jarsigner >/dev/null 2>&1; then
  echo "Android build-tools 36.1.0 (apksigner) and Java jarsigner are required." >&2; exit 1
fi

export ANDROID_HOME="$SDK" ANDROID_SDK_ROOT="$SDK"
export GODOT_ANDROID_KEYSTORE_RELEASE_PATH="$KEYSTORE"
export GODOT_ANDROID_KEYSTORE_RELEASE_USER="$ALIAS"
export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD="$PASSWORD"
cd "$ROOT"

VERSION=$(sed -n 's/^config\/version="\([^"]*\)"/\1/p' project.godot)
if [[ "$VERSION" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
  MAJOR=${BASH_REMATCH[1]}; MINOR=${BASH_REMATCH[2]}; PATCH=${BASH_REMATCH[3]}
else
  echo "project.godot config/version must be numeric MAJOR.MINOR.PATCH." >&2; exit 1
fi
(( MAJOR <= 999 && MINOR <= 999 && PATCH <= 999 )) || { echo "Version components must be <= 999." >&2; exit 1; }
CODE=$((10#$MAJOR * 1000000 + 10#$MINOR * 1000 + 10#$PATCH))
sed -i.bak "s/^version\/code=.*/version\/code=$CODE/" export_presets.cfg
rm -f export_presets.cfg.bak

if [[ ! -f android/.build_version ]] || ! grep -qx '4.7.2.stable' android/.build_version; then
  # Godot installs the Android project template while exporting when this option is set.
  TEMP_AAB=$(mktemp "${TMPDIR:-/tmp}/scaling-laws-template.XXXXXX.aab")
  "$GODOT" --headless --path . --install-android-build-template --export-release "Android AAB" "$TEMP_AAB"
  rm -f "$TEMP_AAB"
fi

mkdir -p build/android
"$GODOT" --headless --path . --import
"$GODOT" --headless --path . --import
"$GODOT" --headless --path . --export-release "Android" build/android/ScalingLaws.apk
"$GODOT" --headless --path . --export-release "Android AAB" build/android/ScalingLaws.aab
test -s build/android/ScalingLaws.apk && test -s build/android/ScalingLaws.aab
"$APKSIGNER" verify --verbose --print-certs build/android/ScalingLaws.apk | tee build/android/apk-signature.txt
grep -q 'Signer #1 certificate DN:' build/android/apk-signature.txt
if grep -Fq 'CN=Android Debug' build/android/apk-signature.txt; then echo "APK is debug-signed" >&2; exit 1; fi
jarsigner -verify -verbose -certs build/android/ScalingLaws.aab | tee build/android/aab-signature.txt
grep -q 'jar verified' build/android/aab-signature.txt
rm build/android/apk-signature.txt build/android/aab-signature.txt
echo "Created build/android/ScalingLaws.apk and build/android/ScalingLaws.aab"
