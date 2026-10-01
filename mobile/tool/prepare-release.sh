#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/android-env.sh"
cd "$MUT_MOBILE_DIR"

if [[ ! -f android/key.properties ]]; then
  echo 'Configure android/key.properties before building. See docs/RELEASE.md.' >&2
  exit 1
fi
if [[ -n "$(git status --porcelain -- .)" ]]; then
  echo 'Commit mobile source changes before building so the APK matches its recorded commit.' >&2
  exit 1
fi
MUT_RELEASE_VERSION="$(sed -n 's/^version: \([^+]*\).*/\1/p' pubspec.yaml)"
MUT_RELEASE_DIR="$MUT_MOBILE_DIR/build/releases/v$MUT_RELEASE_VERSION"
MUT_RELEASE_COMMIT="$(git rev-parse HEAD)"
MUT_RELEASE_BRANCH="$(git branch --show-current)"

"$MUT_FLUTTER" pub get --enforce-lockfile
"$MUT_FLUTTER" analyze
"$MUT_FLUTTER" test
"$MUT_FLUTTER" build apk --release --target-platform android-arm64 --split-per-abi

mkdir -p "$MUT_RELEASE_DIR"
MUT_RELEASE_APK="$MUT_RELEASE_DIR/mut-$MUT_RELEASE_VERSION-android-arm64.apk"
cp build/app/outputs/flutter-apk/app-arm64-v8a-release.apk "$MUT_RELEASE_APK"
cp "docs/releases/$MUT_RELEASE_VERSION.md" "$MUT_RELEASE_DIR/RELEASE_NOTES.md"

MUT_ANDROID_BUILD_TOOLS="$(find "$ANDROID_HOME/build-tools" -mindepth 1 -maxdepth 1 -type d | sort -V | tail -n 1)"
"$MUT_ANDROID_BUILD_TOOLS/apksigner" verify --verbose --print-certs "$MUT_RELEASE_APK" > "$MUT_RELEASE_DIR/SIGNATURE.txt"
"$MUT_ANDROID_BUILD_TOOLS/aapt" dump badging "$MUT_RELEASE_APK" > "$MUT_RELEASE_DIR/APK_INFO.txt"
if ! head -n 1 "$MUT_RELEASE_DIR/APK_INFO.txt" | grep -F "versionName='$MUT_RELEASE_VERSION'" > /dev/null; then
  echo 'APK version does not match pubspec.yaml.' >&2
  exit 1
fi
{
  echo "Version: $MUT_RELEASE_VERSION"
  echo "Source commit: $MUT_RELEASE_COMMIT"
  echo "Source branch: $MUT_RELEASE_BRANCH"
  echo "Built (UTC): $(date -u +%FT%TZ)"
  "$MUT_FLUTTER" --version
} > "$MUT_RELEASE_DIR/BUILD_INFO.txt"
(
  cd "$MUT_RELEASE_DIR"
  sha256sum "mut-$MUT_RELEASE_VERSION-android-arm64.apk" > SHA256SUMS
)
# Detect source changes made while the build was running.
if [[ "$(git rev-parse HEAD)" != "$MUT_RELEASE_COMMIT" || -n "$(git status --porcelain -- .)" ]]; then
  echo 'Source changed during the build; rebuild from a clean commit before publishing.' >&2
  exit 1
fi
printf 'Prepared locally: %s\nSource commit: %s\nNo tags, push or GitHub release were created by this script.\n' "$MUT_RELEASE_DIR" "$MUT_RELEASE_COMMIT"
