#!/usr/bin/env bash
# Twelfth round: GN build system (gn/ninja source tool ports + recipe.gn),
# a real GN-native Crashpad port, and 25 more common C/C++ libraries.
# Static by default. GCPKG_R12_DYNAMIC=1 builds all 28 new ports from a fresh
# store, runs the minimal GN fixture and verifies the merged project compdb.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/build/bin/gcpkg"
PORTS="$ROOT/ports"
CATALOG="$ROOT/tools/r12-catalog.tsv"
NAMES="$(tail -n +2 "$CATALOG" | cut -f1)"
N=$(echo "$NAMES" | wc -w)
mkdir -p /home/user/.cache
T="$(mktemp -d /home/user/.cache/gcpkg-r12-static.XXXXXX)"
trap 'rm -rf "$T"' EXIT
[ "$N" -eq 28 ] || { echo "catalog must have 28 ports, got $N"; exit 1; }
[ -x "$BIN" ] || { echo "build gcpkg first: cmake -S $ROOT -B $ROOT/build && cmake --build $ROOT/build -j"; exit 1; }

echo "== registry: >= 277 ports, two files each, real URLs and SHA256 =="
"$BIN" check --ports "$PORTS" > "$T/check.log" 2>&1
python3 - "$T/check.log" <<'PY' || { cat "$T/check.log"; exit 1; }
import re, sys
n = int(re.search(r"(\d+) ports OK", open(sys.argv[1]).read()).group(1))
print(" ", n, "ports OK")
sys.exit(0 if n >= 277 else 1)
PY
for name in $NAMES; do
    d="$PORTS/$name"
    [ -f "$d/build.lua" ] || { echo "missing $d/build.lua"; exit 1; }
    [ -f "$d/features.yaml" ] || { echo "missing $d/features.yaml"; exit 1; }
    grep -E 'url = "https://' "$d/build.lua" > /dev/null || { echo "no https URL: $name"; exit 1; }
    grep -E 'sha256 = "[0-9a-f]{64}"' "$d/build.lua" > /dev/null || { echo "bad SHA256: $name"; exit 1; }
    if grep -E '/home/user|example\.com|SHA256_HERE|TODO' "$d/build.lua" "$d/features.yaml" > /dev/null; then
        echo "sandbox path or placeholder in $name"; exit 1
    fi
done
echo "  28 ports x (build.lua + features.yaml), all with pinned HTTPS source"

echo "== both generators are byte-for-byte reproducible =="
GCPKG_PORTS="$T/ports" python3 "$ROOT/tools/gen-r12-ports.py" > /dev/null
GCPKG_PORTS="$T/ports" python3 "$ROOT/tools/gen-r12-special-ports.py" > /dev/null
for name in $NAMES; do
    diff -q "$PORTS/$name/build.lua" "$T/ports/$name/build.lua" > /dev/null ||
        { echo "generator drift: $name/build.lua"; exit 1; }
    diff -q "$PORTS/$name/features.yaml" "$T/ports/$name/features.yaml" > /dev/null ||
        { echo "generator drift: $name/features.yaml"; exit 1; }
done
echo "  catalog + 2 generators regenerate all 28 ports"

echo "== GN adapter, source tool ports and Crashpad =="
grep -F 'function M.gn' "$ROOT/lua/gcpkg/recipe.lua" > /dev/null
grep -F 'require("gcpkg.build.gn")' "$ROOT/lua/gcpkg/recipe.lua" > /dev/null
grep -F 'gn, python, cargo' "$ROOT/lua/gcpkg/recipe.lua" > /dev/null
[ -f "$ROOT/lua/gcpkg/build/gn.lua" ]
grep -F -- '--export-compile-commands' "$ROOT/lua/gcpkg/build/gn.lua" > /dev/null
grep -F 'compdb_files' "$ROOT/lua/gcpkg/build/gn.lua" > /dev/null
grep -F 'recipe.gn' "$PORTS/crashpad/build.lua" > /dev/null
grep -F 'dependencies = { "ninja" }' "$PORTS/gn/build.lua" > /dev/null
grep -F 'dependencies = { "gn" }' "$PORTS/crashpad/build.lua" > /dev/null
grep -F 'clang_path' "$PORTS/crashpad/build.lua" > /dev/null
grep -F 'recipe.cmake' "$PORTS/ninja/build.lua" > /dev/null
grep -F 'binaries = { "@PREFIX@/bin" }' "$PORTS/ninja/build.lua" > /dev/null
grep -F 'net.download' "$PORTS/crashpad/build.lua" > /dev/null
grep -F 'net.download' "$PORTS/taglib/build.lua" > /dev/null
[ "$(grep -cE 'sha256 = "[0-9a-f]{64}"' "$PORTS/crashpad/build.lua")" -eq 3 ] ||
    { echo "crashpad needs 3 pinned tarballs"; exit 1; }
[ "$(grep -cE 'sha256 = "[0-9a-f]{64}"' "$PORTS/taglib/build.lua")" -eq 2 ] ||
    { echo "taglib needs 2 pinned tarballs"; exit 1; }
echo "  recipe.gn + gn.lua + ninja/gn/crashpad/toolchain shims + pinned submodules OK"

echo "== bottom-up graphs and conditional dependencies =="
"$BIN" graph crashpad --ports "$PORTS" > "$T/graph-crashpad.log" 2>&1
grep -F 'ninja' "$T/graph-crashpad.log" > /dev/null
grep -F 'gn' "$T/graph-crashpad.log" > /dev/null
grep -F 'crashpad' "$T/graph-crashpad.log" > /dev/null
[ "$(grep -c '^\[gcpkg:info\]' "$T/graph-crashpad.log")" -eq 3 ] ||
    { echo "crashpad chain is not ninja -> gn -> crashpad"; cat "$T/graph-crashpad.log"; exit 1; }
"$BIN" graph libgit2 --ports "$PORTS" > "$T/graph-libgit2.log" 2>&1
grep -F 'zlib' "$T/graph-libgit2.log" > /dev/null
[ "$(grep -c '^\[gcpkg:info\]' "$T/graph-libgit2.log")" -eq 2 ] ||
    { echo "libgit2 chain is not zlib -> libgit2"; exit 1; }
"$BIN" graph taglib --ports "$PORTS" > "$T/graph-taglib.log" 2>&1
if grep -F 'zlib' "$T/graph-taglib.log" > /dev/null; then
    echo "zlib leaked into the default taglib graph"; exit 1
fi
[ "$(grep -c '^\[gcpkg:info\]' "$T/graph-taglib.log")" -eq 1 ] ||
    { echo "default taglib graph is not one step"; exit 1; }
"$BIN" graph taglib --ports "$PORTS" --feature=taglib:zlib > "$T/graph-taglib-zlib.log" 2>&1
grep -F 'zlib' "$T/graph-taglib-zlib.log" > /dev/null
grep -F 'taglib' "$T/graph-taglib-zlib.log" > /dev/null
[ "$(grep -c '^\[gcpkg:info\]' "$T/graph-taglib-zlib.log")" -eq 2 ] ||
    { echo "taglib:zlib chain is not zlib -> taglib"; exit 1; }
"$BIN" features taglib --ports "$PORTS" 2>&1 | grep -F 'zlib' > /dev/null
grep -F 'WITH_ZLIB = "OFF"' "$PORTS/taglib/build.lua" > /dev/null
grep -F 'args: ["-DWITH_ZLIB=ON"]' "$PORTS/taglib/features.yaml" > /dev/null
echo "  crashpad 3-step chain, libgit2/zlib, taglib:zlib conditional chain OK"

echo "== minimal GN fixture and documentation =="
for f in .gn BUILD.gn hello.cc build/BUILDCONFIG.gn build/toolchain/BUILD.gn; do
    [ -f "$ROOT/tests/fixtures/gn-simple/$f" ] || { echo "missing GN fixture $f"; exit 1; }
done
grep -F 'set_default_toolchain' "$ROOT/tests/fixtures/gn-simple/build/BUILDCONFIG.gn" > /dev/null
grep -F 'executable("hello")' "$ROOT/tests/fixtures/gn-simple/BUILD.gn" > /dev/null
[ -f "$ROOT/docs/GN.md" ] && [ -f "$ROOT/docs/ROUND12_LIBRARIES.md" ]
grep -F '277' "$ROOT/README.md" > /dev/null
grep -F '277' "$PORTS/README.md" > /dev/null
grep -F 'recipe.gn' "$ROOT/docs/EXTENDING.md" > /dev/null
grep -F 'GN' "$ROOT/docs/TOOLCHAINS.md" > /dev/null
echo "  fixture + GN/round-12 docs OK"

echo "== earlier rounds did not regress =="
"$BIN" graph cpp-httplib --feature=tls --ports "$PORTS" 2>&1 | grep -F 'openssl' > /dev/null
"$BIN" graph cpp-httplib --feature=tls --ports "$PORTS" 2>&1 | grep -F 'zlib' > /dev/null
"$BIN" graph libvpx --ports "$PORTS" 2>&1 | grep -F 'nasm' > /dev/null
"$BIN" versions zlib --ports "$PORTS" 2>&1 | grep -F '1.2.13' > /dev/null
"$BIN" --help 2>&1 | grep -F 'gcpkg new DIR' > /dev/null
"$BIN" --help 2>&1 | grep -F 'gcpkg proxy [URL|--unset]' > /dev/null
echo "  tls chain, nasm SIMD, multi-version zlib, project + proxy CLI OK"

if [ "${GCPKG_R12_DYNAMIC:-0}" != "1" ]; then
    echo "round-12 GN test OK (static)"
    exit 0
fi

echo "== dynamic: really build all 28 new ports from a fresh store =="
STORE="${GCPKG_R12_STORE:-/home/user/.cache/gcpkg-r12-test-store}"
LOGS="${GCPKG_R12_LOGS:-/home/user/.cache/gcpkg-r12-test-logs}"
ONLY="${GCPKG_R12_ONLY:-}"
rm -rf "$STORE" "$LOGS"
mkdir -p "$STORE" "$LOGS"
PASS=0; FAIL=0; TOTAL=0; EXPECTED=$N
if [ -n "$ONLY" ]; then EXPECTED=$(echo "$ONLY" | wc -w); fi
for name in $NAMES; do
    # Exact whitespace-delimited match: grep -w would treat "ms-gsl" as "gsl".
    if [ -n "$ONLY" ]; then
        case " $ONLY " in *" $name "*) ;; *) continue ;; esac
    fi
    local_args=()
    if [ "$name" = "taglib" ]; then local_args=(--feature=taglib:zlib); fi
    if timeout 1200 "$BIN" install "$name" --store "$STORE" --ports "$PORTS" -j 2 \
        "${local_args[@]}" > "$LOGS/$name.log" 2>&1; then
        RESULT=$(python3 - "$STORE" "$name" <<'PY'
import glob, json, os, sys
store, name = sys.argv[1], sys.argv[2]
files = glob.glob(os.path.join(store, "manifest", name + "-*.json"))
if not files:
    print("ERR manifest"); raise SystemExit
m = json.load(open(files[0]))
prefix = m["prefix"]
missing = []
for lib in m.get("libs", []):
    libdir = os.path.join(prefix, "lib")
    if not (os.path.isfile(os.path.join(libdir, "lib%s.a" % lib)) or
            glob.glob(os.path.join(libdir, "lib%s.so*" % lib))):
        missing.append(lib)
for inc in m.get("includes", []):
    if not os.path.isdir(inc):
        missing.append("include:" + inc)
for b in m.get("binaries", []):
    if not os.path.exists(b):
        missing.append("binary:" + b)
print("ERR missing: " + ",".join(missing) if missing else str(m.get("compdb_entries", 0)))
PY
)
        if [[ "$RESULT" == ERR* ]]; then
            echo "  FAIL $name :: $RESULT"; FAIL=$((FAIL + 1))
        else
            echo "  PASS $name compdb=$RESULT"; PASS=$((PASS + 1)); TOTAL=$((TOTAL + RESULT))
        fi
    else
        echo "  FAIL $name :: $(tail -3 "$LOGS/$name.log" | tr '\n' ' ' | cut -c1-180)"
        FAIL=$((FAIL + 1))
    fi
done

if [ -z "$ONLY" ]; then
    echo "== dynamic: GN tools, native Crashpad artifacts and minimal fixture =="
    GN_BIN=$(find "$STORE/pkg" -path '*/bin/gn' -type f | head -1)
    NINJA_BIN=$(find "$STORE/pkg" -path '*/bin/ninja' -type f | head -1)
    [ -n "$GN_BIN" ] || { echo "gn binary missing"; FAIL=$((FAIL + 1)); }
    [ -n "$NINJA_BIN" ] || { echo "ninja binary missing"; FAIL=$((FAIL + 1)); }
    if [ -n "$GN_BIN" ]; then "$GN_BIN" --version > "$T/gn-version.log" 2>&1 || { echo "gn --version failed"; FAIL=$((FAIL + 1)); }; fi
    if [ -n "$NINJA_BIN" ]; then "$NINJA_BIN" --version > "$T/ninja-version.log" 2>&1 || { echo "ninja --version failed"; FAIL=$((FAIL + 1)); }; fi
    CRASHPAD_PREFIX=$(python3 - "$STORE" <<'PY'
import glob, json, os, sys
m = json.load(open(glob.glob(os.path.join(sys.argv[1], "manifest", "crashpad-*.json"))[0]))
print(m["prefix"])
PY
)
    for lib in libclient.a libcommon.a libutil.a libcompat.a libbase.a; do
        [ -f "$CRASHPAD_PREFIX/lib/$lib" ] || { echo "crashpad $lib missing"; FAIL=$((FAIL + 1)); }
    done
    python3 - "$STORE" <<'PY' || { echo "crashpad GN compdb too small"; FAIL=$((FAIL + 1)); }
import glob, json, os, sys
m = json.load(open(glob.glob(os.path.join(sys.argv[1], "manifest", "crashpad-*.json"))[0]))
assert m.get("compdb_entries", 0) >= 300, m.get("compdb_entries", 0)
print("  crashpad native GN compdb:", m["compdb_entries"])
PY
    FIX="$T/gn-fixture"
    rm -rf "$FIX"; cp -a "$ROOT/tests/fixtures/gn-simple" "$FIX"
    if [ -n "$GN_BIN" ] && [ -n "$NINJA_BIN" ]; then
        (
            cd "$FIX"
            rm -rf out
            PATH="$(dirname "$GN_BIN"):$(dirname "$NINJA_BIN"):$PATH" \
                "$GN_BIN" gen out --export-compile-commands > "$T/gn-fixture.log" 2>&1 &&
            PATH="$(dirname "$GN_BIN"):$(dirname "$NINJA_BIN"):$PATH" \
                "$NINJA_BIN" -C out -j2 hello >> "$T/gn-fixture.log" 2>&1 &&
            ./out/hello >> "$T/gn-fixture.log" 2>&1
        ) || { echo "minimal GN fixture failed"; tail -20 "$T/gn-fixture.log"; FAIL=$((FAIL + 1)); }
        grep -F 'gcpkg GN adapter OK' "$T/gn-fixture.log" > /dev/null || { echo "GN fixture output wrong"; FAIL=$((FAIL + 1)); }
        python3 - "$FIX/out/compile_commands.json" <<'PY' || { echo "GN fixture compdb missing"; FAIL=$((FAIL + 1)); }
import json, sys
assert len(json.load(open(sys.argv[1]))) >= 1
print("  minimal GN fixture: gen + ninja + run + compdb OK")
PY
    fi

    echo "== dynamic: conditional zlib and unified project compdb =="
    TAGLIB_CACHE=$(find "$STORE/build" -path '*taglib*/CMakeCache.txt' | head -1)
    [ -n "$TAGLIB_CACHE" ] || { echo "taglib CMakeCache missing"; FAIL=$((FAIL + 1)); }
    if [ -n "$TAGLIB_CACHE" ]; then
        grep -F 'WITH_ZLIB:BOOL=ON' "$TAGLIB_CACHE" > /dev/null || { echo "taglib:zlib did not enable WITH_ZLIB"; FAIL=$((FAIL + 1)); }
        grep -F "$STORE" "$TAGLIB_CACHE" > /dev/null || { echo "taglib did not see gcpkg store prefixes"; FAIL=$((FAIL + 1)); }
    fi
    LIBGIT2_CACHE=$(find "$STORE/build" -path '*libgit2*/CMakeCache.txt' | head -1)
    [ -n "$LIBGIT2_CACHE" ] || { echo "libgit2 CMakeCache missing"; FAIL=$((FAIL + 1)); }
    if [ -n "$LIBGIT2_CACHE" ]; then
        grep -F "$STORE" "$LIBGIT2_CACHE" > /dev/null || { echo "libgit2 did not see gcpkg zlib prefix"; FAIL=$((FAIL + 1)); }
    fi
    [ -f "$STORE/manifest/zlib-1.3.1.json" ] || { echo "zlib dependency manifest missing"; FAIL=$((FAIL + 1)); }

    PROJECT="$T/gn-project"
    rm -rf "$PROJECT"; mkdir -p "$PROJECT"
    export GCPKG_HOME="$STORE"
    if "$BIN" new "$PROJECT/app" --name=gn-app --ports "$PORTS" > "$T/gn-project.log" 2>&1 &&
       "$BIN" add crashpad -C "$PROJECT/app" --ports "$PORTS" >> "$T/gn-project.log" 2>&1 &&
       "$BIN" install -C "$PROJECT/app" --ports "$PORTS" >> "$T/gn-project.log" 2>&1 &&
       (cd "$PROJECT/app" && "$BIN" compdb --ports "$PORTS") >> "$T/gn-project.log" 2>&1; then
        python3 - "$PROJECT/app/compile_commands.json" "$STORE" <<'PY' || { echo "merged project compdb failed"; FAIL=$((FAIL + 1)); }
import json, os, sys
db = json.load(open(sys.argv[1]))
store = sys.argv[2]
assert len(db) >= 718, len(db)
blob = "\n".join(e["file"] for e in db)
for layer in ("crashpad-", "gn-", "ninja-"):
    assert layer in blob, layer
for e in db:
    assert os.path.isabs(e["file"]), e["file"]
    assert os.path.isfile(e["file"]), "stale source: " + e["file"]
print("  merged project compdb:", len(db), "entries, all source paths valid")
PY
    else
        echo "project compdb command failed"; tail -20 "$T/gn-project.log"; FAIL=$((FAIL + 1))
    fi
fi

echo "  $PASS PASS / $FAIL FAIL, $TOTAL compile commands"
[ "$FAIL" -eq 0 ] || exit 1
[ "$PASS" -eq "$EXPECTED" ] || { echo "expected $EXPECTED installs, got $PASS"; exit 1; }
echo "round-12 GN test OK (dynamic: $PASS/$EXPECTED really built)"
