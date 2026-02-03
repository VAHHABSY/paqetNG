#!/usr/bin/env bash
# Build static libpcap for Android using the NDK.
# Usage: ./scripts/build-libpcap-android.sh [arm64-v8a|armeabi-v7a|x86|x86_64]
# Run from paqetNG repo root. Requires: ANDROID_NDK_HOME or ANDROID_NDK_ROOT set, flex, bison, autoconf, automake, libtool

set -e

ABI="${1:-arm64-v8a}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$REPO_DIR/build/android"
LIBPCAP_SRC="$BUILD_DIR/libpcap-src"
OUT_DIR="$BUILD_DIR/libpcap/$ABI"
NDK="${ANDROID_NDK_HOME:-$ANDROID_NDK_ROOT}"
# Normalize Windows path for bash (e.g. e:\SDK -> E:/SDK)
case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) NDK="${NDK//\\/\/}" ;; esac

if [ -z "$NDK" ]; then
	echo "ANDROID_NDK_HOME or ANDROID_NDK_ROOT must be set" >&2
	exit 1
fi

# NDK prebuilt host tag (linux-x86_64, darwin-x86_64, darwin-arm64, windows-x86_64)
UNAME_S="$(uname -s)"
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

# On Windows, NDK may use .exe or no extension
# armeabi-v7a: use softfp and -marm so libpcap matches Go's android/arm (armelf_linux_eabi; Go uses -marm).
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
	echo "NDK clang not found: $CLANG_BASE (or .exe)" >&2
	exit 1
fi

mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

# Use release tarball when possible (has configure pre-generated; no autogen needed — works on Windows).
LIBPCAP_VERSION="1.10.4"
LIBPCAP_TAR="libpcap-${LIBPCAP_VERSION}.tar.gz"
LIBPCAP_URL="https://www.tcpdump.org/release/${LIBPCAP_TAR}"

if [ ! -d "$LIBPCAP_SRC" ] || [ ! -f "$LIBPCAP_SRC/configure" ]; then
	if [ ! -f "$LIBPCAP_SRC/configure" ] && [ -d "$LIBPCAP_SRC" ]; then
		rm -rf "$LIBPCAP_SRC"
	fi
	if [ ! -d "$LIBPCAP_SRC" ]; then
		if command -v curl &>/dev/null; then
			echo "Downloading libpcap ${LIBPCAP_VERSION}..."
			curl -sL "$LIBPCAP_URL" -o "$BUILD_DIR/$LIBPCAP_TAR" || true
		elif command -v wget &>/dev/null; then
			echo "Downloading libpcap ${LIBPCAP_VERSION}..."
			wget -q -O "$BUILD_DIR/$LIBPCAP_TAR" "$LIBPCAP_URL" || true
		fi
		if [ -f "$BUILD_DIR/$LIBPCAP_TAR" ]; then
			echo "Extracting libpcap..."
			tar xzf "$BUILD_DIR/$LIBPCAP_TAR" -C "$BUILD_DIR"
			mv "$BUILD_DIR/libpcap-${LIBPCAP_VERSION}" "$LIBPCAP_SRC"
			rm -f "$BUILD_DIR/$LIBPCAP_TAR"
		fi
		if [ ! -d "$LIBPCAP_SRC" ]; then
			echo "Cloning libpcap (requires autogen.sh)..."
			git clone --depth 1 https://github.com/the-tcpdump-group/libpcap.git "$LIBPCAP_SRC"
		fi
	fi
	cd "$LIBPCAP_SRC"
	if [ ! -f configure ]; then
		./autogen.sh
	fi
fi

cd "$LIBPCAP_SRC"

# Use a separate build dir per ABI so we never reuse object files from another ABI (e.g. arm64 .o files when building armeabi-v7a).
LIBPCAP_BUILD="$LIBPCAP_SRC/build-$ABI"
rm -rf "$LIBPCAP_BUILD"
mkdir -p "$LIBPCAP_BUILD"
cd "$LIBPCAP_BUILD"

mkdir -p "$OUT_DIR"
export CC="$CLANG"
export CFLAGS="--sysroot=$NDK_SYSROOT -fPIC $FLOAT_ABI $ARM_FLAGS"
export LDFLAGS="--sysroot=$NDK_SYSROOT $FLOAT_ABI $ARM_FLAGS"
../configure --host="$HOST" --with-pcap=linux --disable-shared --enable-static \
	--prefix=/usr --disable-dbus --disable-usb --disable-bluetooth

make -j"$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)"
make install DESTDIR="$OUT_DIR"

# Normalize layout: DESTDIR/usr/include -> OUT_DIR/include, DESTDIR/usr/lib -> OUT_DIR/lib
if [ -d "$OUT_DIR/usr" ]; then
	mkdir -p "$OUT_DIR/include" "$OUT_DIR/lib"
	cp -a "$OUT_DIR/usr/include/"* "$OUT_DIR/include/" 2>/dev/null || true
	cp -a "$OUT_DIR/usr/lib/"* "$OUT_DIR/lib/" 2>/dev/null || true
	rm -rf "$OUT_DIR/usr"
fi

# Ensure static lib is present
if [ -f "$OUT_DIR/lib/libpcap.a" ]; then
	echo "Built libpcap for $ABI at $OUT_DIR"
else
	echo "Build failed: libpcap.a not found" >&2
	exit 1
fi
