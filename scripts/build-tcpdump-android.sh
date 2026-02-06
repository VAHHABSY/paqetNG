#!/usr/bin/env bash
# Build static tcpdump for Android using NDK and our libpcap.
# Usage: ./scripts/build-tcpdump-android.sh [arm64-v8a|armeabi-v7a|x86|x86_64]
# Run from paqetNG repo root. Requires: ANDROID_NDK_HOME, libpcap already built (run build-libpcap-android.sh first).
# Output: build/android/tcpdump/<ABI>/tcpdump

set -e

UNAME_S="$(uname -s)"
ABI="${1:-arm64-v8a}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$REPO_DIR/build/android"
LIBPCAP_DIR="$BUILD_DIR/libpcap/$ABI"
TCPDUMP_SRC="$BUILD_DIR/tcpdump-src"
OUT_DIR="$BUILD_DIR/tcpdump/$ABI"
NDK="${ANDROID_NDK_HOME:-$ANDROID_NDK_ROOT}"
case "$UNAME_S" in MINGW*|MSYS*|CYGWIN*) NDK="${NDK//\\/\/}" ;; esac

if [ -z "$NDK" ]; then
	echo "ANDROID_NDK_HOME or ANDROID_NDK_ROOT must be set" >&2
	exit 1
fi

if [ ! -f "$LIBPCAP_DIR/lib/libpcap.a" ]; then
	echo "libpcap not found at $LIBPCAP_DIR. Run: ./scripts/build-libpcap-android.sh $ABI" >&2
	exit 1
fi

# On Windows (MSYS/Git Bash), NDK clang is a native .exe and needs Windows-style paths for -I/-L
case "$UNAME_S" in
	MINGW*|MSYS*|CYGWIN*)
		if command -v cygpath &>/dev/null; then
			LIBPCAP_DIR="$(cygpath -w "$LIBPCAP_DIR")"
		else
			# /c/Users/... -> C:/Users/...
			LIBPCAP_DIR="$(echo "$LIBPCAP_DIR" | sed 's|^/\([a-zA-Z]\)/|\1:/|')"
		fi
		;;
esac
UNAME_M="$(uname -m)"
case "$UNAME_S" in
	Linux)   HOST_TAG="linux-x86_64" ;;
	Darwin)  [ "$UNAME_M" = "arm64" ] && HOST_TAG="darwin-arm64" || HOST_TAG="darwin-x86_64" ;;
	MINGW*|MSYS*|CYGWIN*) HOST_TAG="windows-x86_64" ;;
	*)       echo "Unsupported host: $UNAME_S" >&2; exit 1 ;;
esac

NDK_BIN="$NDK/toolchains/llvm/prebuilt/$HOST_TAG/bin"
NDK_SYSROOT="$NDK/toolchains/llvm/prebuilt/$HOST_TAG/sysroot"
API="21"

ARM_FLAGS=""
FLOAT_ABI=""
case "$ABI" in
	arm64-v8a)
		HOST="aarch64-linux-android"
		CLANG_BASE="$NDK_BIN/${HOST}${API}-clang"
		;;
	armeabi-v7a)
		HOST="armv7a-linux-androideabi"
		CLANG_BASE="$NDK_BIN/${HOST}${API}-clang"
		FLOAT_ABI="-mfloat-abi=softfp"
		ARM_FLAGS="-marm"
		;;
	x86)
		HOST="i686-linux-android"
		CLANG_BASE="$NDK_BIN/${HOST}${API}-clang"
		;;
	x86_64)
		HOST="x86_64-linux-android"
		CLANG_BASE="$NDK_BIN/${HOST}${API}-clang"
		;;
	*)
		echo "Unsupported ABI: $ABI (use arm64-v8a, armeabi-v7a, x86, or x86_64)" >&2
		exit 1
		;;
esac

if [ -x "$CLANG_BASE" ] || [ -f "$CLANG_BASE" ]; then
	CLANG="$CLANG_BASE"
elif [ -x "${CLANG_BASE}.exe" ] || [ -f "${CLANG_BASE}.exe" ]; then
	CLANG="${CLANG_BASE}.exe"
else
	echo "NDK clang not found: $CLANG_BASE" >&2
	exit 1
fi

mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

# Use release tarball (has configure pre-generated, no autoconf needed). Fall back to git clone.
TCPDUMP_VERSION="4.99.6"
TCPDUMP_TAR="tcpdump-${TCPDUMP_VERSION}.tar.gz"
TCPDUMP_URL="https://www.tcpdump.org/release/${TCPDUMP_TAR}"

if [ ! -d "$TCPDUMP_SRC" ] || [ ! -f "$TCPDUMP_SRC/configure" ]; then
	if [ ! -f "$TCPDUMP_SRC/configure" ] && [ -d "$TCPDUMP_SRC" ]; then
		rm -rf "$TCPDUMP_SRC"
	fi
	if [ ! -d "$TCPDUMP_SRC" ]; then
		if command -v curl &>/dev/null; then
			echo "Downloading tcpdump ${TCPDUMP_VERSION}..."
			curl -sL "$TCPDUMP_URL" -o "$BUILD_DIR/$TCPDUMP_TAR" || true
		elif command -v wget &>/dev/null; then
			echo "Downloading tcpdump ${TCPDUMP_VERSION}..."
			wget -q -O "$BUILD_DIR/$TCPDUMP_TAR" "$TCPDUMP_URL" || true
		fi
		if [ -f "$BUILD_DIR/$TCPDUMP_TAR" ]; then
			echo "Extracting tcpdump..."
			tar xzf "$BUILD_DIR/$TCPDUMP_TAR" -C "$BUILD_DIR"
			mv "$BUILD_DIR/tcpdump-${TCPDUMP_VERSION}" "$TCPDUMP_SRC"
			rm -f "$BUILD_DIR/$TCPDUMP_TAR"
		fi
		if [ ! -d "$TCPDUMP_SRC" ]; then
			echo "Cloning tcpdump from git (requires autoconf for ./autogen.sh)..."
			git clone --depth 1 https://github.com/the-tcpdump-group/tcpdump.git "$TCPDUMP_SRC"
		fi
	fi
	cd "$TCPDUMP_SRC"
	if [ ! -f configure ]; then
		./autogen.sh
	fi
fi

cd "$TCPDUMP_SRC"

TCPDUMP_BUILD="$TCPDUMP_SRC/build-$ABI"
rm -rf "$TCPDUMP_BUILD"
mkdir -p "$TCPDUMP_BUILD"
cd "$TCPDUMP_BUILD"

# On Windows we use prebuilt libpcap (glibc-built); it needs __gnu_strerror_r, stdin/stdout/stderr, getifaddrs stubs. Compile shim and pass to configure.
LDFLAGS_EXTRA=""
case "$UNAME_S" in
	MINGW*|MSYS*|CYGWIN*)
		"$CLANG" $CFLAGS -c "$SCRIPT_DIR/gnu_strerror_r.c" -o gnu_strerror_r.o
		_shim_path="$PWD/gnu_strerror_r.o"
		if command -v cygpath &>/dev/null; then
			_shim_path="$(cygpath -w "$_shim_path")"
		else
			_shim_path="$(echo "$_shim_path" | sed 's|^/\([a-zA-Z]\)/|\1:/|' | sed 's|/|\\|g')"
		fi
		LDFLAGS_EXTRA="$_shim_path"
		;;
esac

export CC="$CLANG"
export CPPFLAGS="-I$LIBPCAP_DIR/include"
export CFLAGS="--sysroot=$NDK_SYSROOT -fPIC -I$LIBPCAP_DIR/include $FLOAT_ABI $ARM_FLAGS"
export LDFLAGS="--sysroot=$NDK_SYSROOT -L$LIBPCAP_DIR/lib $FLOAT_ABI $ARM_FLAGS $LDFLAGS_EXTRA -Wl,-z,max-page-size=16384"
export LIBS="-lpcap -lc"
# Prevent configure from using host pkg-config
export PKG_CONFIG=""
# Pass LDFLAGS and LIBS on command line so generated Makefile definitely uses them (bionic shim + -lc)
# Tell configure libpcap provides these (cross-compile link tests fail; without this tcpdump compiles its own copies → duplicate symbol errors)
../configure --host="$HOST" --with-pcap=linux --without-crypto --disable-smb \
	LDFLAGS="--sysroot=$NDK_SYSROOT -L$LIBPCAP_DIR/lib $FLOAT_ABI $ARM_FLAGS $LDFLAGS_EXTRA -Wl,-z,max-page-size=16384" \
	LIBS="-lpcap -lc" \
	ac_cv_func_pcap_loop=yes \
	ac_cv_func_pcap_list_datalinks=yes \
	ac_cv_func_pcap_free_datalinks=yes \
	ac_cv_func_pcap_datalink_val_to_name=yes \
	ac_cv_func_pcap_datalink_name_to_val=yes \
	ac_cv_func_pcap_datalink_val_to_description=yes \
	ac_cv_func_pcap_dump_ftell=yes \
	ac_cv_func_pcap_dump_ftell64=no

make -j"$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)"

mkdir -p "$OUT_DIR"
cp -f tcpdump "$OUT_DIR/tcpdump"

if [ -f "$OUT_DIR/tcpdump" ]; then
	echo "Built tcpdump for $ABI at $OUT_DIR/tcpdump"
else
	echo "Build failed: tcpdump binary not found" >&2
	exit 1
fi
