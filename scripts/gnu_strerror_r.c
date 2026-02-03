/*
 * Shims when linking prebuilt libpcap (built against glibc) on Android/bionic.
 * - __gnu_strerror_r: glibc internal; bionic has strerror_r with different signature.
 * - stdin/stdout/stderr: glibc exposes them as symbols; bionic uses __sF.
 * - getifaddrs/freeifaddrs: not in bionic before API 24; we use API 21. Stub so link succeeds.
 * - ftello64: prebuilt libpcap may reference it; bionic has ftello (64-bit with LFS).
 */
#define _FILE_OFFSET_BITS 64
#include <string.h>
#include <stdio.h>
#include <sys/types.h>

/* --- __gnu_strerror_r --- */
char *__gnu_strerror_r(int errnum, char *buf, size_t buflen) {
	(void)strerror_r(errnum, buf, buflen);
	return buf;
}

/* --- stdin / stdout / stderr (bionic uses __sF) --- */
#undef stdin
#undef stdout
#undef stderr
extern FILE __sF[3];
FILE *stdin  = &__sF[0];
FILE *stdout = &__sF[1];
FILE *stderr = &__sF[2];

/* --- getifaddrs / freeifaddrs (API 24+ in bionic; stub for API 21) --- */
struct ifaddrs;

int getifaddrs(struct ifaddrs **ifap) {
	*ifap = NULL;
	return 0;
}

void freeifaddrs(struct ifaddrs *ifa) {
	(void)ifa;
}

/* --- ftello64 (prebuilt libpcap on 32-bit; use ftell when ftello not available) --- */
off_t ftello64(FILE *stream) {
	return (off_t)ftell(stream);
}
