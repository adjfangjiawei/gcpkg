#!/bin/sh
# Official LLVM binary installer helper for Linux / WSL (WSL == Linux here).
# This never builds LLVM from source and never edits the project tree.
set -eu

VERSION="${1:-}"
URL="https://apt.llvm.org/llvm.sh"
if [ -z "$VERSION" ]; then
    echo "usage: llvm-install.sh <llvm-version>   (e.g. 23)" >&2
    exit 2
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
SCRIPT="$TMP/llvm.sh"

echo "+ wget https://apt.llvm.org/llvm.sh"
wget -q -O "$SCRIPT" "$URL"
echo "+ chmod +x llvm.sh"
chmod +x "$SCRIPT"
echo "+ sudo ./llvm.sh $VERSION"
if [ "$(id -u)" -eq 0 ]; then
    "$SCRIPT" "$VERSION"
elif command -v sudo >/dev/null 2>&1; then
    sudo "$SCRIPT" "$VERSION"
else
    echo "llvm-install.sh needs root or sudo to run the official installer" >&2
    exit 1
fi

echo "+ gcpkg llvm use /usr/lib/llvm-$VERSION"
echo "After installation: gcpkg llvm use /usr/lib/llvm-$VERSION (or your LLVM root)"
echo "Then: gcpkg toolchain && gcpkg install llvm"
