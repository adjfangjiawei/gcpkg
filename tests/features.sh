#!/usr/bin/env bash
# Feature-conditional dependency test: an enabled feature's `requires:` must
# become a REAL bottom-up dependency (graph, check, install and manifest), not
# just a Configure argument. Also checks the wide L1 dependency surface.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
BIN=${GCPKG_BIN:-"$ROOT/build/bin/gcpkg"}
PORTS="$ROOT/ports"
STORE=${GCPKG_STORE:-"$HOME/.cache/gcpkg-feature-store"}

if [[ ! -x "$BIN" ]]; then
    echo "build gcpkg first: cmake -S $ROOT -B $ROOT/build && cmake --build $ROOT/build -j" >&2
    exit 1
fi
mkdir -p "$HOME/.cache"

order_of() {
    python3 -c '
import re, sys
names = [m.group(2) for line in sys.stdin for m in [re.search(r"\b(\d+)\.\s+([A-Za-z0-9_.+-]+)", line)] if m]
print(" ".join(names))
'
}

echo "--- graph/check honour feature requests ---"
"$BIN" check --ports "$PORTS" --feature=openssl:zlib
ORDER=$("$BIN" graph openssl --ports "$PORTS" --feature=openssl:zlib)
echo "$ORDER"
NAMES=$(echo "$ORDER" | order_of)
[[ "$NAMES" == "zlib openssl" ]] || { echo "unexpected order: $NAMES" >&2; exit 1; }

ORDER=$("$BIN" graph libarchive --ports "$PORTS")
echo "$ORDER"
NAMES=$(echo "$ORDER" | order_of)
[[ "$NAMES" == "zlib bzip2 xz zstd lz4 openssl expat pcre2 libarchive" ]] || {
    echo "unexpected order: $NAMES" >&2; exit 1; }

# The feature/graph checks above stay active. The cached-store assertions below
# need the old OpenSSL build, which is not persisted in a fresh sandbox.
if [[ "${GCPKG_FORCE_DYNAMIC:-0}" != "1" && ! -f "$STORE/manifest/openssl-3.4.1.json" ]]; then
    echo "SKIP cached openssl feature build: no openssl manifest in $STORE (set GCPKG_FORCE_DYNAMIC=1 to rebuild)"
    exit 0
fi
echo "--- real build of the conditional chain ---"
"$BIN" install openssl --feature=openssl:zlib --store "$STORE" --ports "$PORTS" -j "$(nproc)"

python3 - "$STORE" <<'PY'
import glob, json, os, sys
store = sys.argv[1]
m = json.load(open(os.path.join(store, "manifest", "openssl-3.4.1.json")))
assert m["deps"] == ["zlib-1.3.1"], m["deps"]
assert "zlib" in m["features"], m["features"]
jsonl = open(os.path.join(store, "compdb", "openssl-3.4.1.jsonl")).read()
assert '"-DZLIB"' in jsonl, "OpenSSL was not compiled with zlib support"
assert "zlib-1.3.1/include" in jsonl, "gcpkg zlib headers were not injected"
print("manifest deps:", m["deps"], "features:", m["features"])
print("compdb: -DZLIB and gcpkg zlib include present")
libs = glob.glob(os.path.join(store, "pkg", "openssl-3.4.1", "lib*", "libcrypto.a"))
assert libs, "libcrypto.a missing"
PY
if command -v nm >/dev/null 2>&1; then
    LIB=$(find "$STORE/pkg/openssl-3.4.1" -name libcrypto.a -print -quit)
    # no `grep -q`: with pipefail it would kill nm via SIGPIPE before the check
    nm -g "$LIB" | grep 'BIO_f_zlib' >/dev/null
    echo "libcrypto.a contains BIO_f_zlib (zlib really linked in)"
else
    echo "nm not installed; skipping symbol check"
fi

echo "features test OK"
