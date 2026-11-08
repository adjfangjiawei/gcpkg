#!/usr/bin/env bash
# Tenth round: 38 more libraries + the proxy engine. Static by default;
# GCPKG_R10_DYNAMIC=1 really builds all 38 ports from a clean store.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$(pwd)
BIN="$ROOT/build/bin/gcpkg"
CATALOG="$ROOT/tools/r10-catalog.tsv"
NAMES=$(tail -n +2 "$CATALOG" | cut -f1)
N=$(echo "$NAMES" | wc -w)
T=$(mktemp -d /home/user/.cache/gcpkg-r10-test.XXXXXX)
trap 'rm -rf "$T"' EXIT
[ "$N" -eq 38 ] || { echo "catalog must have 38 ports, got $N"; exit 1; }

echo "== registry: >= 226 ports, files, real URLs and SHA256 =="
"$BIN" check --ports "$ROOT/ports" > "$T/check.log" 2>&1
python3 - "$T/check.log" <<'PY' || { echo "registry check failed"; exit 1; }
import re, sys
n = int(re.search(r"(\d+) ports OK", open(sys.argv[1]).read()).group(1))
print(" ", n, "ports OK")
sys.exit(0 if n >= 226 else 1)
PY
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
python3 "$ROOT/tools/gen-r10-ports.py" > /dev/null
HASH2=$(tail -n +2 "$CATALOG" | cut -f1 | while read -r n; do cat "ports/$n/build.lua" "ports/$n/features.yaml"; done | sha256sum | cut -d' ' -f1)
[ "$HASH1" = "$HASH2" ] || { echo "generator is not reproducible"; exit 1; }
echo "  catalog + generator regenerate byte-identical ports"

echo "== bottom-up chains =="
for spec in "re2:2:abseil" "glog:2:gflags" "libbsd:2:libmd"; do
    port_name=${spec%%:*}; rest=${spec#*:}; steps=${rest%%:*}; dep=${rest##*:}
    "$BIN" graph "$port_name" --ports "$ROOT/ports" > "$T/graph-$port_name.log" 2>&1
    grep -F "$dep" "$T/graph-$port_name.log" > /dev/null || { echo "$port_name chain lost $dep"; exit 1; }
    [ "$(grep -c '^\[gcpkg:info\]' "$T/graph-$port_name.log")" -eq "$steps" ] ||
        { echo "$port_name chain is not $steps steps"; exit 1; }
done
echo "  re2(2) / glog(2) / libbsd(2) bottom-up chains OK"

echo "== feature-conditional dependencies and build switches =="
"$BIN" graph libsrtp --ports "$ROOT/ports" > "$T/default.log" 2>&1
if grep -F "openssl" "$T/default.log" > /dev/null; then
    echo "openssl leaked into the default libsrtp graph"; exit 1
fi
for pair in "libsrtp:openssl:openssl" "mosquitto:tls:openssl" "srt:tls:openssl" \
            "libcoap:tls:openssl" "portaudio:alsa:alsa-lib" \
            "libdwarf:compression:zlib" "libtomcrypt:ltm:libtommath"; do
    port_name=${pair%%:*}; rest=${pair#*:}; feat=${rest%%:*}; dep=${rest##*:}
    "$BIN" graph "$port_name" --feature="$feat" --ports "$ROOT/ports" > "$T/f.log" 2>&1
    grep -F "$dep" "$T/f.log" > /dev/null || { echo "$feat did not pull $dep"; exit 1; }
done
"$BIN" features libdwarf --ports "$ROOT/ports" 2>&1 | grep -F "compression" > /dev/null
grep -F 'args: ["-DENABLE_OPENSSL=ON"]' "$ROOT/ports/libsrtp/features.yaml" > /dev/null ||
    { echo "feature-gated CMake switch missing"; exit 1; }
echo "  seven optional features resolve; default graphs stay lean"

echo "== earlier rounds did not regress =="
"$BIN" graph libsndfile --ports "$ROOT/ports" 2>&1 | grep -F "flac" > /dev/null
"$BIN" graph udisks2 --ports "$ROOT/ports" 2>&1 | grep -F "liburing" > /dev/null
"$BIN" versions zlib --ports "$ROOT/ports" 2>&1 | grep -F "1.2.13" > /dev/null
"$BIN" --help 2>&1 | grep -F "gcpkg new DIR" > /dev/null
"$BIN" --help 2>&1 | grep -F "gcpkg proxy [URL|--unset]" > /dev/null
echo "  audio chain, disk-info chain, multi-version zlib, project + proxy CLI OK"

if [ "${GCPKG_R10_DYNAMIC:-0}" != "1" ]; then
    echo "round-10 libraries test OK (static)"
    exit 0
fi

echo "== dynamic: really build all 38 ports from a fresh store =="
STORE="${GCPKG_R10_STORE:-/home/user/.cache/gcpkg-r10-test-store}"
LOGS="${GCPKG_R10_LOGS:-/home/user/.cache/gcpkg-r10-test-logs}"
rm -rf "$STORE"
mkdir -p "$STORE" "$LOGS"
PASS=0
FAIL=0
TOTAL=0
for name in $NAMES; do
    if timeout 600 "$BIN" install "$name" --store "$STORE" --ports "$ROOT/ports" -j 2 \
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
echo "  $PASS PASS / $FAIL FAIL, $TOTAL compile commands"
[ "$FAIL" -eq 0 ] || exit 1
[ "$PASS" -eq 38 ] || exit 1
echo "round-10 libraries test OK (dynamic: 38/38 really built)"
