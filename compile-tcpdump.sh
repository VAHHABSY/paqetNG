#!/bin/bash
# Build tcpdump for Android and copy to app assets.
# Requires: ANDROID_NDK_HOME, make (on Windows: Git for Windows provides make in usr/bin).
# Output: app/src/main/assets/{arm64-v8a,armeabi-v7a,x86,x86_64}/tcpdump
set -o errexit
set -o pipefail
set -o nounset
__dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# On Windows, ensure make is on PATH
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*)
    _found=
    _bash_dir="$(dirname "$(command -v bash 2>/dev/null)" 2>/dev/null)"
    # Try: same dir as bash, Git usr/bin, MSYS2, Chocolatey, common locations
    for _d in "$_bash_dir" "/usr/bin" "/mingw64/bin" "/mingw32/bin" \
      "C:/Program Files/Git/usr/bin" "C:/Program Files (x86)/Git/usr/bin" \
      "C:/msys64/usr/bin" "C:/msys64/mingw64/bin" \
      "C:/ProgramData/chocolatey/bin" "C:/ProgramData/chocolatey/lib/make/tools/install/make/bin" \
      "C:/ProgramData/chocolatey/lib/make/tools/bin" "C:/Program Files (x86)/GnuWin32/bin"; do
      [[ -z "$_d" ]] && continue
      _d="${_d//\\/\/}"
      if [[ -x "$_d/make.exe" ]] || [[ -x "$_d/make" ]]; then
        export PATH="$_d:$PATH"
        _found=1
        break
      fi
    done
    if [[ -z "$_found" ]] && ! command -v make &>/dev/null; then
      echo "make not found. On Windows, install one of:"
      echo "  1. MSYS2 (https://www.msys2.org/) then: pacman -S make; add C:\\msys64\\usr\\bin to PATH"
      echo "  2. Chocolatey: choco install make"
      echo "  3. Or run this build from WSL: wsl bash compile-tcpdump.sh"
      exit 1
    fi
    ;;
esac

if [[ -z "${ANDROID_NDK_HOME:-}" ]] && [[ -z "${ANDROID_NDK_ROOT:-}" ]]; then
  echo "Android NDK: ANDROID_NDK_HOME or ANDROID_NDK_ROOT not set."
  exit 1
fi

export ANDROID_NDK_HOME="${ANDROID_NDK_HOME:-${ANDROID_NDK_ROOT}}"
ASSETS="$__dir/app/src/main/assets"
BUILD_OUT="$__dir/build/android"
mkdir -p "$ASSETS/arm64-v8a" "$ASSETS/armeabi-v7a" "$ASSETS/x86" "$ASSETS/x86_64"

# On Windows, use prebuilt libpcap (building from source needs flex/bison). We link a __gnu_strerror_r shim and -lc in build-tcpdump-android.sh.
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*)
    if [[ ! -f "$BUILD_OUT/libpcap/arm64-v8a/lib/libpcap.a" ]]; then
      echo "Setting up prebuilt libpcap for Windows..."
      powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$__dir/scripts/setup-libpcap-windows.ps1"
    fi
    ;;
esac

# Build libpcap (Linux/macOS) or use prebuilt (Windows), then tcpdump.
# On Windows only build ARM (x86/x86_64 need flex/lex for libpcap from source).
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*)
    make -f "$__dir/Makefile.paqet" tcpdump-windows
    cp -f "$BUILD_OUT/tcpdump/arm64-v8a/tcpdump" "$ASSETS/arm64-v8a/tcpdump"
    cp -f "$BUILD_OUT/tcpdump/armeabi-v7a/tcpdump" "$ASSETS/armeabi-v7a/tcpdump"
    echo "Done. tcpdump binaries copied to $ASSETS/{arm64-v8a,armeabi-v7a}/ (ARM only on Windows)"
    ;;
  *)
    make -f "$__dir/Makefile.paqet" tcpdump
    cp -f "$BUILD_OUT/tcpdump/arm64-v8a/tcpdump" "$ASSETS/arm64-v8a/tcpdump"
    cp -f "$BUILD_OUT/tcpdump/armeabi-v7a/tcpdump" "$ASSETS/armeabi-v7a/tcpdump"
    cp -f "$BUILD_OUT/tcpdump/x86/tcpdump" "$ASSETS/x86/tcpdump"
    cp -f "$BUILD_OUT/tcpdump/x86_64/tcpdump" "$ASSETS/x86_64/tcpdump"
    echo "Done. tcpdump binaries copied to $ASSETS/{arm64-v8a,armeabi-v7a,x86,x86_64}/tcpdump"
    ;;
esac
