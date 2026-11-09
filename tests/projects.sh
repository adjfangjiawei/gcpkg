#!/usr/bin/env bash
# Project-workflow regression: pnpm-style new/add/remove/list, three port
# scopes, project-specific dependency lists, per-project version pinning and
# real builds of two different zlib releases side by side.
#
# Default = static (no network, no compiler). Set GCPKG_PROJECT_DYNAMIC=1 to
# download + actually build the pinned versions into a scratch store.
set -euo pipefail

: "${HOME:?HOME must be set}"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}"
mkdir -p "$CACHE_DIR"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
BIN="$ROOT/build/bin/gcpkg"
[ -x "$BIN" ] || { echo "build the engine first: cmake -S . -B build && cmake --build build -j"; exit 1; }

TMP="${GCPKG_PROJECT_TEST_DIR:-$CACHE_DIR/gcpkg-projects-test}"
STORE="$TMP/home"
rm -rf "$TMP"
mkdir -p "$STORE"
export GCPKG_HOME="$STORE"
GP=("$BIN" --store "$STORE" --ports "$ROOT/ports")
LOG="$TMP/commands.log"
OUT="$TMP/last.out"
: > "$LOG"

run() { echo "+ $*" >> "$LOG"; "${GP[@]}" "$@" >> "$LOG" 2>&1; }
capture() { echo "+ $*" >> "$LOG"; "${GP[@]}" "$@" > "$OUT" 2>&1; cat "$OUT" >> "$LOG"; }
has() { grep -F "$1" "$LOG" > /dev/null; }
lasthas() { grep -F "$1" "$OUT" > /dev/null; }
assert() { if ! eval "$1"; then echo "FAILED: $1"; tail -25 "$LOG"; exit 1; fi; }

echo "== registry still intact =="
capture check
python3 - "$OUT" <<'PY'
import re, sys
text = open(sys.argv[1]).read()
n = int(re.search(r"(\d+) ports OK", text).group(1))
assert n >= 145, n   # registry is forward compatible
print("registry:", n, "ports OK")
PY
capture graph udisks2
lasthas "liburing"
lasthas "libnvme"

echo "== pnpm-style new =="
run new "$TMP/app-a" --name=app-a
run new "$TMP/app-b" --name=app-b
for p in app-a app-b; do
    for f in gcpkg.lua gcpkg.yaml src/main.c gcpkg-ports/README.md .gitignore; do
        assert "test -f '$TMP/$p/$f'"
    done
    assert "grep -F 'gcpkg-ports' '$TMP/$p/gcpkg.yaml' > /dev/null"
    assert "grep -F 'dependencies: []' '$TMP/$p/gcpkg.yaml' > /dev/null"
done
assert "grep -F 'name = \"app-a\"' '$TMP/app-a/gcpkg.lua' > /dev/null"

echo "== different projects, different libraries and versions =="
run add zlib@1.2.13 -C "$TMP/app-a"
run add zlib@1.3.1 -C "$TMP/app-b"
assert "grep -F 'zlib@1.2.13' '$TMP/app-a/gcpkg.yaml' > /dev/null"
assert "grep -F 'zlib@1.3.1' '$TMP/app-b/gcpkg.yaml' > /dev/null"
assert "! grep -F 'zlib@1.3.1' '$TMP/app-a/gcpkg.yaml' > /dev/null"
assert "grep -F '\"zlib@1.2.13\"' '$TMP/app-a/gcpkg.lock' > /dev/null"
assert "grep -F '\"pending\": true' '$TMP/app-a/gcpkg.lock' > /dev/null"

# Replacing the version of an existing dependency is an in-place edit.
run add zlib@1.2.11 -C "$TMP/app-a"
assert "grep -F 'zlib@1.2.11' '$TMP/app-a/gcpkg.yaml' > /dev/null"
assert "! grep -F 'zlib@1.2.13' '$TMP/app-a/gcpkg.yaml' > /dev/null"
run add zlib@1.2.13 -C "$TMP/app-a"

echo "== versions: declared releases are real URLs + SHA256 =="
capture versions zlib
for v in 1.3.1 1.2.13 1.2.12 1.2.11; do lasthas "$v"; done
lasthas "zlib.net/fossils/zlib-1.2.12.tar.gz"
capture versions jansson
for v in 2.15.1 2.14 2.13.1 2.12; do lasthas "$v"; done
lasthas "refs/tags/v2.14"
# `versions:` is metadata, never a "feature".
capture features zlib
lasthas "no-examples"
assert "! grep -F 'versions' '$OUT' > /dev/null"

echo "== undeclared versions are rejected, not silently faked =="
if "${GP[@]}" add zlib@9.9.9 -C "$TMP/app-a" >> "$LOG" 2>&1; then
    echo "FAILED: undeclared version was accepted"; exit 1
fi
has "has no version '9.9.9'"

echo "== project-private port (--local) =="
run add mydisklib --local -C "$TMP/app-a"
assert "test -f '$TMP/app-a/gcpkg-ports/mydisklib/build.lua'"
assert "test -f '$TMP/app-a/gcpkg-ports/mydisklib/features.yaml'"
assert "grep -F 'mydisklib' '$TMP/app-a/gcpkg.yaml' > /dev/null"
capture list -C "$TMP/app-a"
lasthas "[project]"
lasthas "port=$TMP/app-a/gcpkg-ports/mydisklib"
# Copying an existing public port into the project makes it project-scoped.
run add jansson --local -C "$TMP/app-b"
assert "test -f '$TMP/app-b/gcpkg-ports/jansson/build.lua'"
capture list -C "$TMP/app-b"
lasthas "jansson"
lasthas "[project]"

echo "== global (user-wide) dependency list is opt-in =="
run add -g bzip2
assert "grep -F 'bzip2' '$STORE/gcpkg.yaml' > /dev/null"
capture list -C "$TMP/app-a"
lasthas "global deps    : 1 (not inherited)"
sed -i 's/inherit_global: false/inherit_global: true/' "$TMP/app-a/gcpkg.yaml"
capture list -C "$TMP/app-a"
lasthas "global deps    : 1 (inherited)"
run remove bzip2 -g
assert "! grep -F -- '- bzip2' '$STORE/gcpkg.yaml' > /dev/null"

echo "== remove =="
run remove mydisklib -C "$TMP/app-a"
assert "! grep -F 'mydisklib' '$TMP/app-a/gcpkg.yaml' > /dev/null"
run remove jansson -C "$TMP/app-b"
assert "! grep -F -- '- jansson' '$TMP/app-b/gcpkg.yaml' > /dev/null"

echo "== managed block does not destroy the rest of gcpkg.yaml =="
assert "grep -F 'features: {}' '$TMP/app-a/gcpkg.yaml' > /dev/null"
assert "grep -F '# --- gcpkg managed dependencies' '$TMP/app-a/gcpkg.yaml' > /dev/null"

if [ "${GCPKG_PROJECT_DYNAMIC:-0}" != "1" ]; then
    echo "project workflow test OK (static)"
    exit 0
fi

echo "== dynamic: two projects really build two different zlib releases =="
run new "$TMP/v1" --name=v1
run new "$TMP/v2" --name=v2
run add zlib@1.2.13 -C "$TMP/v1"
run add zlib@1.3.1 jansson@2.14 -C "$TMP/v2"
# `install` with no argument installs the whole project's dependencies.
run install -C "$TMP/v2"
has "project dependencies installed"
run build "$TMP/v1"
run build "$TMP/v2"

PASS=0
for spec in "v1:1.2.13" "v2:1.3.1"; do
    proj="${spec%%:*}"; ver="${spec##*:}"
    other="1.3.1"; [ "$ver" = "1.3.1" ] && other="1.2.13"
    N=$(python3 - "$TMP" "$STORE" "$proj" "$ver" "$other" <<'PY'
import json, sys
tmp, store, proj, ver, other = sys.argv[1:]
lock = json.load(open(f'{tmp}/{proj}/gcpkg.lock'))
keys = [r['key'] for r in lock['resolved']]
assert f'zlib-{ver}' in keys, (proj, keys)
cc = json.load(open(f'{tmp}/{proj}/compile_commands.json'))
blob = json.dumps(cc)
assert f'zlib-{ver}' in blob, (proj, 'wrong zlib in compdb')
assert f'zlib-{other}' not in blob, (proj, 'version leak across projects')
m = json.load(open(f'{store}/manifest/zlib-{ver}.json'))
assert m['compdb_entries'] > 0, (proj, 'empty compdb')
assert m['version'] == ver, (proj, m['version'])
print(len(cc))
PY
) || { echo "FAILED: $proj/$ver"; exit 1; }
    echo "  $proj -> zlib-$ver: $N merged compile commands"
    PASS=$((PASS + 1))
done
python3 - "$TMP" "$STORE" <<'PY'
import json, sys
tmp, store = sys.argv[1:]
m = json.load(open(f'{store}/manifest/jansson-2.14.json'))
assert m['compdb_entries'] > 0
lock = json.load(open(f'{tmp}/v2/gcpkg.lock'))
assert 'jansson-2.14' in [r['key'] for r in lock['resolved']]
a = json.load(open(f'{tmp}/v1/gcpkg.lock'))['resolved'][0]['key']
b = [r['key'] for r in lock['resolved']]
assert a not in b, (a, b)
print('  distinct resolved keys:', a, 'vs', b)
PY
echo "project workflow test OK (dynamic: $PASS projects, 3 freshly built libraries)"
