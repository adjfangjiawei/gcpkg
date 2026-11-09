#!/usr/bin/env bash
# Toolchain ports: registry, dependency graphs and optional real builds.
# Set GCPKG_TOOLCHAIN_PORTS_DYNAMIC=1 to build the catalog into a fresh store.
# Rust ports are omitted when rustc/cargo is unavailable.
set -euo pipefail

: "${HOME:?HOME must be set}"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}"
mkdir -p "$CACHE_DIR"
cd "$(dirname "$0")/.."
ROOT=$(pwd)
BIN="$ROOT/build/bin/gcpkg"
CATALOG="$ROOT/tools/toolchain-catalog.tsv"
NAMES="$(tail -n +2 "$CATALOG" | cut -f1) nasm python rust tokenizers-cpp toml ryu"
N=$(echo "$NAMES" | wc -w)
CN=$(tail -n +2 "$CATALOG" | wc -l)
T=$(mktemp -d ${HOME:-.}/.cache/gcpkg-toolchain-ports-test.XXXXXX)
trap 'rm -rf "$T"' EXIT
[ "$CN" -eq 17 ] || { echo "catalog must have 17 ports, got $CN"; exit 1; }
[ "$N" -eq 23 ] || { echo "expected 23 new ports, got $N"; exit 1; }

echo "== registry: >= 249 ports, files, real URLs and SHA256 =="
"$BIN" check --ports "$ROOT/ports" > "$T/check.log" 2>&1
python3 - "$T/check.log" <<'PY' || { echo "registry check failed"; exit 1; }
import re, sys
n = int(re.search(r"(\d+) ports OK", open(sys.argv[1]).read()).group(1))
print(" ", n, "ports OK")
sys.exit(0 if n >= 249 else 1)
PY
for name in $NAMES; do
    d="$ROOT/ports/$name"
    [ -f "$d/build.lua" ] || { echo "missing $d/build.lua"; exit 1; }
    [ -f "$d/features.yaml" ] || { echo "missing $d/features.yaml"; exit 1; }
    if [ "$name" != rust ]; then
        grep -E 'url = "https://' "$d/build.lua" > /dev/null || { echo "no https URL: $name"; exit 1; }
        grep -E 'sha256 = "[0-9a-f]{64}"' "$d/build.lua" > /dev/null || { echo "bad SHA256: $name"; exit 1; }
    fi
    if grep -E 'example\.com|SHA256_HERE|TODO' "$d/build.lua" "$d/features.yaml" > /dev/null; then
        echo "sandbox path or placeholder in $name"; exit 1
    fi
done
echo "  23 ports x (build.lua + features.yaml), 22 with real URL/SHA256"

echo "== both generators are reproducible =="
GCPKG_PORTS="$T/ports" python3 "$ROOT/tools/gen-toolchain-ports.py" > /dev/null
GCPKG_PORTS="$T/ports" python3 "$ROOT/tools/gen-polyglot-ports.py" > /dev/null
for name in $NAMES; do
    diff -q "$ROOT/ports/$name/build.lua" "$T/ports/$name/build.lua" > /dev/null ||
        { echo "generator drift: $name/build.lua"; exit 1; }
    diff -q "$ROOT/ports/$name/features.yaml" "$T/ports/$name/features.yaml" > /dev/null ||
        { echo "generator drift: $name/features.yaml"; exit 1; }
done
echo "  catalog + 2 generators regenerate byte-identical ports"

echo "== tool ports, adapters and the external Rust port =="
grep -F 'require("gcpkg.build.python")' "$ROOT/lua/gcpkg/recipe.lua" > /dev/null
grep -F 'require("gcpkg.build.cargo")' "$ROOT/lua/gcpkg/recipe.lua" > /dev/null
grep -F 'function M.python' "$ROOT/lua/gcpkg/recipe.lua" > /dev/null
grep -F 'function M.cargo' "$ROOT/lua/gcpkg/recipe.lua" > /dev/null
[ -f "$ROOT/lua/gcpkg/build/python.lua" ] && [ -f "$ROOT/lua/gcpkg/build/cargo.lua" ]
grep -F 'recipe.python' "$ROOT/ports/toml/build.lua" > /dev/null
grep -F 'recipe.cargo' "$ROOT/ports/ryu/build.lua" > /dev/null
grep -F 'GCPKG_RUST_HOME' "$ROOT/ports/rust/build.lua" > /dev/null
grep -F 'external.declare' "$ROOT/ports/rust/build.lua" > /dev/null
"$BIN" externals --ports "$ROOT/ports" 2>&1 | grep -E '^\[gcpkg:info\] +rust +GCPKG_RUST_HOME' > /dev/null
grep -F 'bin/cargo' "$ROOT/ports/rust/build.lua" > /dev/null
echo "  recipe.python / recipe.cargo + rust external declaration OK"

echo "== nasm is a real SOURCE tool port and libvpx consumes it =="
grep -F 'version = "2.16.03"' "$ROOT/ports/nasm/build.lua" > /dev/null
grep -F 'binaries =' "$ROOT/ports/nasm/build.lua" > /dev/null
grep -F '"--as=nasm"' "$ROOT/ports/libvpx/build.lua" > /dev/null
grep -F '"--target=x86_64-linux-gcc"' "$ROOT/ports/libvpx/build.lua" > /dev/null
if grep -F 'generic-gnu' "$ROOT/ports/libvpx/build.lua" > /dev/null; then
    echo "libvpx fell back to the pure-C target"; exit 1
fi
grep -F 'libvpx' "$ROOT/tools/extra-catalog.tsv" | grep -F 'nasm' > /dev/null
echo "  nasm source port -> libvpx SIMD configure (no generic-gnu fallback)"

echo "== tokenizers-cpp: pinned upstream revision + 3 pinned tarballs =="
grep -F 'c586c52f93f7b060753bd2388eb96a105cb7374d' "$ROOT/ports/tokenizers-cpp/build.lua" > /dev/null
[ "$(grep -cE 'sha256 = "[0-9a-f]{64}"' "$ROOT/ports/tokenizers-cpp/build.lua")" -eq 3 ] ||
    { echo "expected 3 pinned tarballs"; exit 1; }
grep -F 'net.download' "$ROOT/ports/tokenizers-cpp/build.lua" > /dev/null
grep -F 'compdb_files' "$ROOT/ports/tokenizers-cpp/build.lua" > /dev/null
grep -F 'dependencies = { "rust" }' "$ROOT/ports/tokenizers-cpp/build.lua" > /dev/null
echo "  Rust -> C -> C++ binding, empty submodules filled from pinned tarballs"

echo "== bottom-up dependency chains =="
for spec in "libvpx:2:nasm" "toml:2:python" "pybind11:2:python" \
            "ryu:2:rust" "tokenizers-cpp:2:rust"; do
    port_name=${spec%%:*}; rest=${spec#*:}; steps=${rest%%:*}; dep=${rest##*:}
    "$BIN" graph "$port_name" --ports "$ROOT/ports" > "$T/graph-$port_name.log" 2>&1
    grep -F "$dep" "$T/graph-$port_name.log" > /dev/null || { echo "$port_name chain lost $dep"; exit 1; }
    [ "$(grep -c '^\[gcpkg:info\]' "$T/graph-$port_name.log")" -eq "$steps" ] ||
        { echo "$port_name chain is not $steps steps"; exit 1; }
done
echo "  libvpx/toml/pybind11/ryu/tokenizers-cpp chains OK"

echo "== feature-conditional deps (default graphs stay lean) =="
if "$BIN" graph cpp-httplib --ports "$ROOT/ports" 2>&1 | grep -F 'openssl' > /dev/null; then
    echo "openssl leaked into the default cpp-httplib graph"; exit 1
fi
"$BIN" graph cpp-httplib --feature=tls --ports "$ROOT/ports" > "$T/tls.log" 2>&1
grep -F 'openssl' "$T/tls.log" > /dev/null && grep -F 'zlib' "$T/tls.log" > /dev/null
"$BIN" graph onetbb --feature=python --ports "$ROOT/ports" > "$T/tbb.log" 2>&1
grep -F 'python' "$T/tbb.log" > /dev/null
grep -F 'description: Build shared libraries' "$ROOT/ports/sentencepiece/features.yaml" > /dev/null
grep -F 'HWY_ENABLE_CONTRIB = "OFF"' "$ROOT/ports/highway/build.lua" > /dev/null
grep -F 'jobs = 2,' "$ROOT/ports/sentencepiece/build.lua" > /dev/null
echo "  cpp-httplib:tls / onetbb:python / sentencepiece:shared / highway switch OK"

echo "== registry and CLI compatibility =="
"$BIN" graph libsndfile --ports "$ROOT/ports" 2>&1 | grep -F 'flac' > /dev/null
"$BIN" graph udisks2 --ports "$ROOT/ports" 2>&1 | grep -F 'liburing' > /dev/null
"$BIN" versions zlib --ports "$ROOT/ports" 2>&1 | grep -F '1.2.13' > /dev/null
"$BIN" --help 2>&1 | grep -F 'gcpkg new DIR' > /dev/null
"$BIN" --help 2>&1 | grep -F 'gcpkg proxy [URL|--unset]' > /dev/null
[ -f "$ROOT/docs/PORTS.md" ] && [ -f "$ROOT/docs/CONFIGURATION.md" ]
echo "  audio chain, disk-info chain, multi-version zlib, project + proxy CLI OK"

if [ "${GCPKG_TOOLCHAIN_PORTS_DYNAMIC:-0}" != "1" ]; then
    echo "toolchain ports toolchains test OK (static)"
    exit 0
fi

echo "== dynamic: really build all 23 new ports + libvpx from a fresh store =="
STORE="${GCPKG_TOOLCHAIN_PORTS_STORE:-${HOME:-.}/.cache/gcpkg-toolchain-ports-test-store}"
LOGS="${GCPKG_TOOLCHAIN_PORTS_LOGS:-${HOME:-.}/.cache/gcpkg-toolchain-ports-test-logs}"
rm -rf "$STORE" "$LOGS"
mkdir -p "$STORE" "$LOGS"
RUST_OK=0
if [ -n "${CARGO_HOME:-}" ] && [ -x "$CARGO_HOME/bin/cargo" ]; then
    export GCPKG_RUST_HOME="${GCPKG_RUST_HOME:-$CARGO_HOME}"
    export PATH="$CARGO_HOME/bin:$PATH"
    RUST_OK=1
elif command -v cargo > /dev/null 2>&1; then
    CARGO_DIR=$(dirname "$(dirname "$(command -v cargo)")")
    export GCPKG_RUST_HOME="${GCPKG_RUST_HOME:-$CARGO_DIR}"
    RUST_OK=1
fi
if [ "$RUST_OK" -ne 1 ]; then
    echo "  WARNING: no rustc/cargo; rust, ryu, tokenizers-cpp remain STATIC only"
fi
PASS=0; FAIL=0; TOTAL=0
for name in $NAMES libvpx; do
    if [ "$RUST_OK" -ne 1 ]; then
        case "$name" in rust|ryu|tokenizers-cpp) continue ;; esac
    fi
    if timeout 900 "$BIN" install "$name" --store "$STORE" --ports "$ROOT/ports" -j 2 \
        > "$LOGS/$name.log" 2>&1; then
        RESULT=$(python3 - "$STORE" "$name" <<'PY'
import glob, json, os, sys
files = glob.glob(sys.argv[1] + '/manifest/' + sys.argv[2] + '-*.json')
if not files:
    print('ERR manifest'); raise SystemExit
m = json.load(open(files[0]))
missing = []
for lib in m.get('libs', []):
    libdir = m['prefix'] + '/lib'
    found = False
    if os.path.isdir(libdir):
        found = (os.path.exists(libdir + '/lib%s.a' % lib)
                 or any(x.startswith('lib%s.so' % lib) for x in os.listdir(libdir)))
    if not found:
        missing.append(lib)
print('ERR missing libs: ' + ','.join(missing) if missing else str(m.get('compdb_entries', 0)))
PY
)
        if [[ "$RESULT" == ERR* ]]; then
            echo "  FAIL $name :: $RESULT"; FAIL=$((FAIL + 1))
        else
            echo "  PASS $name compdb=$RESULT"; PASS=$((PASS + 1)); TOTAL=$((TOTAL + RESULT))
        fi
    else
        echo "  FAIL $name :: $(tail -3 "$LOGS/$name.log" | tr '\n' ' ' | cut -c1-160)"
        FAIL=$((FAIL + 1))
    fi
done

echo "== extra dynamic checks =="
[ -x "$STORE/pkg/nasm-2.16.03/bin/nasm" ] || { echo "nasm binary missing"; FAIL=$((FAIL + 1)); }
LOG="$STORE/logs/libvpx-1.15.0.log"
if [ -f "$LOG" ]; then
    grep -F 'using nasm' "$LOG" > /dev/null || { echo "libvpx did not detect nasm"; FAIL=$((FAIL + 1)); }
    grep -F '[AS]' "$LOG" > /dev/null || { echo "libvpx did not assemble SIMD"; FAIL=$((FAIL + 1)); }
fi
[ -x "$STORE/pkg/python-3.12.8/bin/python3" ] || { echo "CPython missing"; FAIL=$((FAIL + 1)); }
[ -f "$STORE/pkg/python-3.12.8/lib/libpython3.12.a" ] || { echo "libpython missing"; FAIL=$((FAIL + 1)); }
[ -d "$STORE/pkg/toml-0.10.2/lib/python3/site-packages/toml" ] ||
    { echo "toml site-packages missing"; FAIL=$((FAIL + 1)); }
if [ -x "$STORE/pkg/python-3.12.8/bin/python3" ]; then
    "$STORE/pkg/python-3.12.8/bin/python3" -c \
        'import sys; sys.path.insert(0, "'"$STORE"'/pkg/toml-0.10.2/lib/python3/site-packages"); import toml; assert toml.loads("a = 1")["a"] == 1' ||
        { echo "python adapter import failed"; FAIL=$((FAIL + 1)); }
fi
if [ "$RUST_OK" -eq 1 ]; then
    [ -f "$STORE/pkg/ryu-1.0.18/lib/libryu.rlib" ] || { echo "ryu rlib missing"; FAIL=$((FAIL + 1)); }
    TK=$(find "$STORE/pkg" -maxdepth 1 -name 'tokenizers-cpp-*' -type d | head -1)
    [ -n "$TK" ] || { echo "tokenizers-cpp prefix missing"; FAIL=$((FAIL + 1)); }
    for lib in libtokenizers_cpp.a libtokenizers_c.a libsentencepiece.a; do
        [ -f "$TK/lib/$lib" ] || { echo "$lib missing"; FAIL=$((FAIL + 1)); }
    done
    [ -f "$TK/include/tokenizers_cpp.h" ] || { echo "tokenizers_cpp.h missing"; FAIL=$((FAIL + 1)); }
    cat > "$T/link.cpp" <<'CPP'
#include "tokenizers_cpp.h"
int main() { auto f = &tokenizers::Tokenizer::FromBlobJSON; (void)f; return 0; }
CPP
    g++ -std=c++17 "$T/link.cpp" -I"$TK/include" -L"$TK/lib" \
        -Wl,--start-group -ltokenizers_cpp -ltokenizers_c -lsentencepiece -lonig -Wl,--end-group \
        -lpthread -ldl -lm -o "$T/link" ||
        { echo "C++/Rust static link failed"; FAIL=$((FAIL + 1)); }
    "$T/link" || { echo "linked binary did not run"; FAIL=$((FAIL + 1)); }
    echo "  C++ -> C -> Rust static link + run OK"
fi
echo "  $PASS PASS / $FAIL FAIL, $TOTAL compile commands"
[ "$FAIL" -eq 0 ] || exit 1
EXPECTED=21
[ "$RUST_OK" -eq 1 ] && EXPECTED=24
[ "$PASS" -eq "$EXPECTED" ] || { echo "expected $EXPECTED installs, got $PASS"; exit 1; }
if [ "$RUST_OK" -eq 1 ]; then
    echo "toolchain ports toolchains test OK (dynamic: 24/24 really built)"
else
    echo "toolchain ports toolchains test OK (dynamic: 21 built, 3 Rust ports static only)"
fi
