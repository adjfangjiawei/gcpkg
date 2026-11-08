#!/usr/bin/env bash
# Ninth-round regression: 43 more base libraries (data formats, compression,
# QUIC/network, audio/video, crypto, C++ tooling) plus conditional features
# and bottom-up dependency chains.
#
# Default = static (no network, no compiler). With GCPKG_EXTRA_DYNAMIC=1 it
# downloads and really builds ALL 43 ports into a fresh scratch store.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
BIN="$ROOT/build/bin/gcpkg"
[ -x "$BIN" ] || { echo "build the engine first: cmake -S . -B build && cmake --build build -j"; exit 1; }

CATALOG="$ROOT/tools/extra-catalog.tsv"
NAMES=$(tail -n +2 "$CATALOG" | cut -f1)
N=$(echo "$NAMES" | wc -w)
[ "$N" -eq 43 ] || { echo "catalog must have 43 ports, got $N"; exit 1; }

echo "== registry: >= 188 ports, files, real URLs and SHA256 =="
"$BIN" check --ports "$ROOT/ports" 2>&1 | python3 -c 'import re,sys; n=int(re.search(r"(\d+) ports OK",sys.stdin.read()).group(1)); sys.exit(0 if n >= 188 else 1)'
for name in $NAMES; do
    d="$ROOT/ports/$name"
    [ -f "$d/build.lua" ] || { echo "missing $d/build.lua"; exit 1; }
    [ -f "$d/features.yaml" ] || { echo "missing $d/features.yaml"; exit 1; }
    grep -E 'url = "https://' "$d/build.lua" > /dev/null || { echo "no https URL: $name"; exit 1; }
    grep -E 'sha256 = "[0-9a-f]{64}"' "$d/build.lua" > /dev/null || { echo "bad SHA256: $name"; exit 1; }
    if grep -E '/home/user|example\.com|SHA256_HERE|TODO' "$d/build.lua" "$d/features.yaml" > /dev/null; then
        echo "sandbox path or placeholder in $name"; exit 1
    fi
done
echo "  $N ports x (build.lua + features.yaml), real URL/SHA256, no sandbox paths"

echo "== generator is reproducible =="
HASH1=$(tail -n +2 "$CATALOG" | cut -f1 | while read -r n; do cat "ports/$n/build.lua" "ports/$n/features.yaml"; done | sha256sum | cut -d' ' -f1)
python3 "$ROOT/tools/gen-extra-ports.py" > /dev/null
HASH2=$(tail -n +2 "$CATALOG" | cut -f1 | while read -r n; do cat "ports/$n/build.lua" "ports/$n/features.yaml"; done | sha256sum | cut -d' ' -f1)
[ "$HASH1" = "$HASH2" ] || { echo "generator is not reproducible"; exit 1; }
echo "  catalog + generator regenerate byte-identical ports"

echo "== bottom-up chains =="
"$BIN" graph libsndfile --ports "$ROOT/ports" > /tmp/gcpkg-extra-graph1.log 2>&1
for p in libogg libvorbis opus flac libsndfile; do grep -F "$p" /tmp/gcpkg-extra-graph1.log > /dev/null; done
[ "$(grep -c '^\[gcpkg:info\]' /tmp/gcpkg-extra-graph1.log)" -eq 5 ] || { echo "libsndfile chain is not 5 steps"; exit 1; }
"$BIN" graph spdlog --ports "$ROOT/ports" > /tmp/gcpkg-extra-graph2.log 2>&1
grep -F "fmt" /tmp/gcpkg-extra-graph2.log > /dev/null
grep -F "spdlog" /tmp/gcpkg-extra-graph2.log > /dev/null
"$BIN" graph libssh --ports "$ROOT/ports" > /tmp/gcpkg-extra-graph3.log 2>&1
grep -F "openssl" /tmp/gcpkg-extra-graph3.log > /dev/null
grep -F "zlib" /tmp/gcpkg-extra-graph3.log > /dev/null
echo "  libsndfile(5) / spdlog(2) / libssh(openssl+zlib) OK"

echo "== feature-conditional dependencies =="
"$BIN" graph libzip --ports "$ROOT/ports" > /tmp/gcpkg-extra-graph4.log 2>&1
if grep -F "openssl" /tmp/gcpkg-extra-graph4.log > /dev/null; then echo "openssl leaked into default libzip graph"; exit 1; fi
for pair in "libzip:openssl" "libwebsockets:tls" "librdkafka:ssl" "ngtcp2:tls"; do
    port_name="${pair%%:*}"; feat="$pair"
    "$BIN" graph "$port_name" --feature="$feat" --ports "$ROOT/ports" > /tmp/gcpkg-extra-graph5.log 2>&1
    grep -F "openssl" /tmp/gcpkg-extra-graph5.log > /dev/null || { echo "$feat did not pull openssl"; exit 1; }
done
"$BIN" features libzip --ports "$ROOT/ports" 2>&1 | grep -F "openssl" > /dev/null
echo "  four optional features resolve; default graphs stay lean"

echo "== earlier rounds did not regress =="
"$BIN" graph udisks2 --ports "$ROOT/ports" 2>&1 | grep -F "liburing" > /dev/null
"$BIN" versions zlib --ports "$ROOT/ports" 2>&1 | grep -F "1.2.13" > /dev/null
"$BIN" --help 2>&1 | grep -F "gcpkg new DIR" > /dev/null
echo "  disk-info chain, multi-version zlib and project CLI still present"

if [ "${GCPKG_EXTRA_DYNAMIC:-0}" != "1" ]; then
    echo "extra libraries test OK (static)"
    exit 0
fi

echo "== dynamic: really build all 43 ports from a fresh store =="
STORE="${GCPKG_EXTRA_STORE:-/home/user/.cache/gcpkg-extra-test-store}"
rm -rf "$STORE"
mkdir -p "$STORE" /home/user/.cache/gcpkg-extra-test-logs
PASS=0
FAIL=0
TOTAL=0
for name in $NAMES; do
    if timeout 420 "$BIN" install "$name" --store "$STORE" --ports "$ROOT/ports" -j 2 \
        > "/home/user/.cache/gcpkg-extra-test-logs/$name.log" 2>&1; then
        C=$(python3 - "$STORE" "$name" <<'PY'
import glob, json, sys
files = glob.glob(sys.argv[1] + '/manifest/' + sys.argv[2] + '-*.json')
print(json.load(open(files[0]))['compdb_entries'] if files else 0)
PY
)
        echo "  PASS $name compdb=$C"
        PASS=$((PASS + 1))
        TOTAL=$((TOTAL + C))
    else
        echo "  FAIL $name :: $(tail -3 /home/user/.cache/gcpkg-extra-test-logs/$name.log | tr '\n' ' ' | cut -c1-160)"
        FAIL=$((FAIL + 1))
    fi
done
echo "  $PASS PASS / $FAIL FAIL, $TOTAL compile commands"
[ "$FAIL" -eq 0 ] || exit 1
[ "$PASS" -eq 43 ] || exit 1
echo "extra libraries test OK (dynamic: 43/43 really built)"
