#!/bin/sh
# Build PaperTerminal's bundled HTTPS stack for the Kindle 3:
# statically linked curl (with OpenSSL inside) + openssl CLI + Mozilla CA
# bundle, targeting ARMv5 EABI soft-float / musl, which runs on the K3's
# ARMv6 CPU and 2.6.26 kernel.
#
# Runs on any x86_64 Linux host (or a GitHub Actions ubuntu runner) with:
#   curl make perl gcc xz tar file
#   qemu-arm-static (optional but strongly recommended - enables the
#                    on-host TLS smoke tests; apt: qemu-user-static)
#
# Usage:
#   build/build-https-stack.sh                 # pinned known-good versions
#   CURL_VERSION=latest OPENSSL_VERSION=latest build/build-https-stack.sh
#
# Output: extensions/paperterminal/lib/{curl,openssl,cacert.pem,
#         BUILDINFO.txt,SHA256SUMS}

set -eu

# ----------------------------------------------------------- versions ------
CURL_VERSION="${CURL_VERSION:-8.21.0}"
OPENSSL_VERSION="${OPENSSL_VERSION:-3.5.7}"
TOOLCHAIN="${TOOLCHAIN:-armv5-eabi--musl--stable-2025.08-1}"

# Publisher-verified pins for the default versions ("" = skip pin check,
# the publisher-hosted .sha256 files are still enforced where they exist).
PIN_CURL_SHA256="aa1b66a70eace83dc624508745646c08ae561de512ab403adffb93ac87fc72e6"
PIN_TOOLCHAIN_SHA256="8cdb4ad70c6b5a66427fa3315fe3ddde1c19c90232674dec59045e04d2a36cf1"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
LIB="$REPO/extensions/paperterminal/lib"
WORK="${WORK:-$REPO/build/.work}"
JOBS="$(nproc 2>/dev/null || echo 2)"
FETCH="curl -sSL --fail --retry 3"

mkdir -p "$WORK" "$LIB"
cd "$WORK"

resolve_latest() {
    if [ "$CURL_VERSION" = "latest" ]; then
        CURL_VERSION="$($FETCH https://curl.se/download/ \
            | grep -oE 'curl-8\.[0-9.]+\.tar\.xz' \
            | sed 's/^curl-//; s/\.tar\.xz$//' | sort -uV | tail -n 1)"
        PIN_CURL_SHA256=""
    fi
    if [ "$OPENSSL_VERSION" = "latest" ]; then
        OPENSSL_VERSION="$($FETCH https://openssl-library.org/source/ \
            | grep -oE 'openssl-3\.[0-9]+\.[0-9]+\.tar\.gz' \
            | sed 's/^openssl-//; s/\.tar\.gz$//' | sort -uV | tail -n 1)"
    fi
    echo "curl $CURL_VERSION, openssl $OPENSSL_VERSION, $TOOLCHAIN"
}

check_sha256() { # file expected-hash label
    got="$(sha256sum "$1" | cut -d' ' -f1)"
    if [ "$got" != "$2" ]; then
        echo "SHA256 MISMATCH for $3: got $got want $2" >&2
        exit 1
    fi
    echo "sha256 ok: $3"
}

download() {
    echo "== downloading"
    $FETCH -O "https://toolchains.bootlin.com/downloads/releases/toolchains/armv5-eabi/tarballs/$TOOLCHAIN.tar.xz"
    $FETCH -O "https://curl.se/download/curl-$CURL_VERSION.tar.xz"
    $FETCH -O "https://github.com/openssl/openssl/releases/download/openssl-$OPENSSL_VERSION/openssl-$OPENSSL_VERSION.tar.gz" \
        || $FETCH -O "https://openssl-library.org/source/openssl-$OPENSSL_VERSION.tar.gz"
    $FETCH -o cacert.pem https://curl.se/ca/cacert.pem
    $FETCH -o cacert.pem.sha256 https://curl.se/ca/cacert.pem.sha256

    # Publisher-hosted hashes (hard requirement).
    OPENSSL_SHA256="$($FETCH "https://github.com/openssl/openssl/releases/download/openssl-$OPENSSL_VERSION/openssl-$OPENSSL_VERSION.tar.gz.sha256" \
        || $FETCH "https://openssl-library.org/source/openssl-$OPENSSL_VERSION.tar.gz.sha256")"
    OPENSSL_SHA256="$(echo "$OPENSSL_SHA256" | tr -d '*' | awk '{print $1}')"
    check_sha256 "openssl-$OPENSSL_VERSION.tar.gz" "$OPENSSL_SHA256" "openssl tarball (publisher)"
    check_sha256 cacert.pem "$(awk '{print $1}' cacert.pem.sha256)" "cacert.pem (publisher)"

    # Local pins for artifacts whose publishers don't post plain hashes.
    [ -n "$PIN_CURL_SHA256" ] && check_sha256 "curl-$CURL_VERSION.tar.xz" "$PIN_CURL_SHA256" "curl tarball (pin)"
    [ -n "$PIN_TOOLCHAIN_SHA256" ] && check_sha256 "$TOOLCHAIN.tar.xz" "$PIN_TOOLCHAIN_SHA256" "toolchain (pin)"

    echo "== extracting"
    tar xf "$TOOLCHAIN.tar.xz"
    tar xf "curl-$CURL_VERSION.tar.xz"
    tar xf "openssl-$OPENSSL_VERSION.tar.gz"
}

build_openssl() {
    echo "== building openssl $OPENSSL_VERSION (static, armv5, devrandom seed)"
    cd "$WORK/openssl-$OPENSSL_VERSION"
    # --with-rand-seed=devrandom: the K3's 2.6.26 kernel has no getrandom()
    ./Configure linux-armv4 \
        --cross-compile-prefix=arm-buildroot-linux-musleabi- \
        --prefix="$WORK/sslout" \
        --openssldir=/mnt/us/extensions/paperterminal/lib/ssl \
        --with-rand-seed=devrandom \
        -static -Os \
        no-shared no-dso no-async no-tests no-docs no-engine no-comp \
        > configure.log
    make -j"$JOBS" > build.log 2>&1
    make install_sw > install.log 2>&1
    cd "$WORK"
}

build_curl() {
    echo "== building curl $CURL_VERSION (static, http/https only)"
    cd "$WORK/curl-$CURL_VERSION"
    # --disable-threaded-resolver: the Kindle's environment cannot spawn
    # resolver threads (curl reports it as 'Out of memory'); blocking DNS
    # is what works there. --disable-ipv6: the K3's 2.6 kernel + v4-only
    # networks make IPv6 lookups pure risk.
    ./configure --host=arm-buildroot-linux-musleabi \
        --with-openssl="$WORK/sslout" \
        --with-ca-bundle=/mnt/us/extensions/paperterminal/lib/cacert.pem \
        --disable-shared --enable-static \
        --disable-threaded-resolver --disable-ipv6 \
        --disable-ldap --disable-ldaps --disable-rtsp --disable-dict \
        --disable-telnet --disable-tftp --disable-pop3 --disable-imap \
        --disable-smb --disable-smtp --disable-gopher --disable-mqtt \
        --disable-ftp --disable-file --disable-ipfs --disable-manual \
        --disable-docs --disable-ntlm --disable-tls-srp --disable-unix-sockets \
        --without-libpsl --without-libidn2 --without-brotli --without-zstd \
        --without-nghttp2 --without-zlib --without-libssh2 \
        CFLAGS="-Os" LDFLAGS="-static -L$WORK/sslout/lib" \
        PKG_CONFIG_PATH="$WORK/sslout/lib/pkgconfig" > configure.log
    # libtool drops plain -static on the final link; -all-static keeps the
    # binary fully static, -no-pie keeps it plain ET_EXEC for the 2.6 kernel
    make -j"$JOBS" LDFLAGS="-all-static -no-pie -L$WORK/sslout/lib" > build.log 2>&1
    cd "$WORK"
}

smoke_test() {
    QEMU="$(command -v qemu-arm-static || command -v qemu-arm || true)"
    if [ -z "$QEMU" ]; then
        echo "== qemu-arm not found - SKIPPING smoke tests" >&2
        return 0
    fi
    echo "== smoke tests under $QEMU"
    export OPENSSL_CONF=/dev/null
    "$QEMU" "$WORK/sslout/bin/openssl" version
    "$QEMU" "$WORK/curl-$CURL_VERSION/src/curl" --version | head -n 1

    "$QEMU" "$WORK/sslout/bin/openssl" req -x509 -newkey rsa:2048 -nodes \
        -keyout t.key -out t.crt -days 2 -subj "/CN=localhost" \
        -addext "subjectAltName=DNS:localhost,IP:127.0.0.1" 2>/dev/null
    echo tls-ok > index.html
    "$QEMU" "$WORK/sslout/bin/openssl" s_server -accept 18443 \
        -cert t.crt -key t.key -WWW -quiet &
    SPID=$!
    sleep 2
    OUT="$("$QEMU" "$WORK/curl-$CURL_VERSION/src/curl" -sS --cacert t.crt \
        https://localhost:18443/index.html)"
    [ "$OUT" = "tls-ok" ] || { echo "TLS1.3 handshake test FAILED" >&2; kill $SPID; exit 1; }
    OUT="$("$QEMU" "$WORK/curl-$CURL_VERSION/src/curl" -sS --tlsv1.2 --tls-max 1.2 \
        --cacert t.crt https://localhost:18443/index.html)"
    [ "$OUT" = "tls-ok" ] || { echo "TLS1.2 handshake test FAILED" >&2; kill $SPID; exit 1; }
    if "$QEMU" "$WORK/curl-$CURL_VERSION/src/curl" -sS --cacert cacert.pem \
        https://localhost:18443/index.html 2>/dev/null; then
        echo "NEGATIVE TEST FAILED: wrong CA was accepted" >&2; kill $SPID; exit 1
    fi
    kill $SPID 2>/dev/null || true
    echo "smoke tests passed (TLS 1.3, TLS 1.2, bad-CA rejected)"
}

build_evkey() {
    echo "== building evkey (input keycode reader)"
    arm-buildroot-linux-musleabi-gcc -Os -static -no-pie \
        -o "$WORK/evkey" "$REPO/build/evkey.c"
}

install_lib() {
    echo "== installing into $LIB"
    STRIP=arm-buildroot-linux-musleabi-strip
    cp "$WORK/curl-$CURL_VERSION/src/curl" "$LIB/curl"
    cp "$WORK/sslout/bin/openssl" "$LIB/openssl"
    cp "$WORK/evkey" "$LIB/evkey"
    cp "$WORK/cacert.pem" "$LIB/cacert.pem"
    "$STRIP" "$LIB/curl" "$LIB/openssl" "$LIB/evkey"
    chmod 755 "$LIB/curl" "$LIB/openssl" "$LIB/evkey"

    cat > "$LIB/BUILDINFO.txt" <<EOF
PaperTerminal bundled HTTPS stack
=================================

These binaries replace the Kindle 3's stock curl/openssl, whose TLS stack
is far too old for today's HTTPS. They are statically linked (musl libc),
so they run with no dependency on anything in the Kindle firmware.

curl        curl $CURL_VERSION with OpenSSL $OPENSSL_VERSION linked in statically.
            Protocols restricted to http/https (+ws/wss). Default CA
            bundle path baked in: /mnt/us/extensions/paperterminal/lib/cacert.pem
openssl     OpenSSL $OPENSSL_VERSION command-line tool (s_client etc. for debugging).
            OPENSSLDIR: /mnt/us/extensions/paperterminal/lib/ssl
cacert.pem  Mozilla CA root certificate bundle as published by the curl
            project (https://curl.se/ca/cacert.pem),
            $(grep -c 'BEGIN CERTIFICATE' "$LIB/cacert.pem") roots.

Target
------
ARMv5 EABI soft-float, statically linked with musl - runs on the Kindle 3
Keyboard (i.MX35, ARM1136 = ARMv6) and its 2.6.26 kernel. OpenSSL is
configured with --with-rand-seed=devrandom because the 2.6 kernel
predates the getrandom() syscall.

Toolchain: Bootlin $TOOLCHAIN (Buildroot)
Built: $(date -u '+%Y-%m-%d %H:%M UTC') by build/build-https-stack.sh

Source tarball hashes at build time
-----------------------------------
$(cd "$WORK" && sha256sum "openssl-$OPENSSL_VERSION.tar.gz" "curl-$CURL_VERSION.tar.xz" "$TOOLCHAIN.tar.xz" cacert.pem)
(openssl + cacert.pem verified against publisher-hosted .sha256 files)
EOF

    (cd "$LIB" && sha256sum curl openssl evkey cacert.pem > SHA256SUMS)
    ls -la "$LIB"
}

export PATH="$WORK/$TOOLCHAIN/bin:$PATH"
resolve_latest
download
build_openssl
build_curl
build_evkey
smoke_test
install_lib
echo "== done"
