#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/android-env.sh"
cd -- "$MUT_MOBILE_DIR"
exec "$MUT_FLUTTER" run "$@"
