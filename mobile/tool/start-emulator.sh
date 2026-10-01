#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/android-env.sh"
MUT_ANDROID_AVD_NAME="${MUT_ANDROID_AVD_NAME:-mut_pixel_api36}"
exec "$ANDROID_HOME/emulator/emulator" -avd "$MUT_ANDROID_AVD_NAME" -gpu auto -no-boot-anim "$@"
