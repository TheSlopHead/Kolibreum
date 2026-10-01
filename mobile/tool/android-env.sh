#!/usr/bin/env bash
# Shared local SDK configuration; source from the launch scripts.
MUT_MOBILE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
MUT_TOOLING_DIR="$MUT_MOBILE_DIR/.tooling"
if [[ -x "$MUT_TOOLING_DIR/flutter/bin/flutter" ]]; then
  MUT_FLUTTER="$MUT_TOOLING_DIR/flutter/bin/flutter"
else
  MUT_FLUTTER="$(command -v flutter)"
fi
if [[ -d "$MUT_TOOLING_DIR/jdk" ]]; then
  export JAVA_HOME="$MUT_TOOLING_DIR/jdk"
fi
if [[ -d "$MUT_TOOLING_DIR/android-sdk" ]]; then
  export ANDROID_HOME="$MUT_TOOLING_DIR/android-sdk"
fi
if [[ -d "$MUT_TOOLING_DIR/pub-cache" ]]; then
  export PUB_CACHE="$MUT_TOOLING_DIR/pub-cache"
fi
export GRADLE_USER_HOME="$MUT_TOOLING_DIR/gradle"
