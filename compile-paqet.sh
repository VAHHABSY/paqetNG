#!/bin/bash
# Build paqet for Android. On Windows uses scripts/build-android-pc.ps1 (prebuilt libpcap).
# On Linux/macOS uses Makefile. Requires: Go, NDK (ANDROID_NDK_HOME), paqet submodule.
# Output: app/src/main/assets/{arm64-v8a,armeabi-v7a,x86,x86_64}/paqet
set -o errexit
set -o pipefail
set -o nounset
__dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v go &>/dev/null; then
  echo "Go not found. Install Go and ensure it is on PATH."
  exit 1
fi

if [[ -z "${ANDROID_NDK_HOME:-}" ]] && [[ -z "${ANDROID_NDK_ROOT:-}" ]]; then
  echo "Android NDK: ANDROID_NDK_HOME or ANDROID_NDK_ROOT not set."
  exit 1
fi

if [[ ! -d "$__dir/paqet" ]]; then
  echo "paqet submodule not found. Run: git submodule update --init paqet"
  exit 1
fi

export ANDROID_NDK_HOME="${ANDROID_NDK_HOME:-${ANDROID_NDK_ROOT}}"
ASSETS="$__dir/app/src/main/assets"
BUILD_OUT="$__dir/build/android"
mkdir -p "$ASSETS/arm64-v8a" "$ASSETS/armeabi-v7a" "$ASSETS/x86" "$ASSETS/x86_64"

# Windows: use our PowerShell script (prebuilt libpcap)
if [[ "$(uname -s)" =~ MINGW|MSYS|CYGWIN ]]; then
  echo "Using scripts/build-android-pc.ps1 (Windows)..."
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$__dir/scripts/build-android-pc.ps1" -NdkPath "$ANDROID_NDK_HOME"
  cp -f "$BUILD_OUT/paqet_android_arm64" "$ASSETS/arm64-v8a/paqet"
  echo "Done. paqet binary copied to $ASSETS/arm64-v8a/paqet (arm64 only on Windows)"
  exit 0
fi

# Linux/macOS: use Makefile.paqet (builds from paqet submodule)
make -f "$__dir/Makefile.paqet" android
cp -f "$BUILD_OUT/paqet_android_arm64"  "$ASSETS/arm64-v8a/paqet"
cp -f "$BUILD_OUT/paqet_android_arm"   "$ASSETS/armeabi-v7a/paqet"
cp -f "$BUILD_OUT/paqet_android_x86"   "$ASSETS/x86/paqet"
cp -f "$BUILD_OUT/paqet_android_x86_64" "$ASSETS/x86_64/paqet"
echo "Done. paqet binaries copied to $ASSETS/{arm64-v8a,armeabi-v7a,x86,x86_64}/paqet"
