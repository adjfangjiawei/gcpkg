#!/usr/bin/env bash
# Install the Debian/Ubuntu packages needed to build gcpkg and its ports.
#
# The list covers the engine (CMake, C++20, Lua, yaml-cpp, curl, pkg-config),
# the build systems used by ports (Meson, Ninja, autotools, Python, NASM), and
# the host development packages consumed through the pkg-config backend.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

sudo apt-get update -qq

sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    cmake \
    ninja-build \
    clang-22 \
    llvm-22-dev \
    libclang-22-dev \
    libcurl4-openssl-dev \
    liblua5.4-dev \
    lua5.4 \
    libyaml-cpp-dev \
    pkg-config \
    git

sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    meson \
    bison \
    flex \
    xsltproc \
    gettext \
    gperf \
    autopoint \
    autoconf \
    automake \
    libtool \
    nasm \
    python3-jinja2 \
    python3-ply

sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    libudev-dev \
    libmtdev-dev \
    libxkbfile-dev \
    libxfont-dev \
    libfontenc-dev \
    libunwind-dev \
    libbsd-dev \
    libxshmfence-dev \
    libx11-xcb-dev \
    libxcb-util-dev \
    libxcb1-dev \
    libdbus-1-dev \
    libdrm-dev \
    libpciaccess-dev \
    libpixman-1-dev \
    xtrans-dev \
    x11-xkb-utils \
    libxkbcommon-dev \
    libgbm-dev \
    libepoxy-dev \
    libselinux1-dev \
    libaudit-dev \
    libpam0g-dev \
    libacl1-dev \
    libcrypt-dev \
    libgcrypt20-dev \
    libidn2-dev \
    libelf-dev \
    libdw-dev \
    libglib2.0-dev \
    libmount-dev \
    libblkid-dev \
    libkmod-dev \
    libseccomp-dev \
    libcap-dev \
    libpcre2-dev \
    liblz4-dev \
    libzstd-dev \
    liblzma-dev \
    zlib1g-dev \
    libssl-dev \
    libffi-dev \
    libexpat1-dev \
    libarchive-dev \
    libgnutls28-dev \
    libp11-kit-dev \
    libqrencode-dev \
    libpwquality-dev \
    libmicrohttpd-dev \
    libfido2-dev \
    libtss2-dev \
    libbpf-dev \
    libcryptsetup-dev \
    libsystemd-dev

cmake --version | head -1
clang++-22 --version | head -1
meson --version
ninja --version
cat <<EOF
Toolchain ready. Build gcpkg with:
  cmake -S "$SCRIPT_DIR" -B "$SCRIPT_DIR/build"
  cmake --build "$SCRIPT_DIR/build" -j
EOF
