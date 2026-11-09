#!/usr/bin/env bash
# Library ports: catalog, registry, global store, Conan surface and optional
# real installation of all 24 libraries into one store.
set -euo pipefail

: "${HOME:?HOME must be set}"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}"
mkdir -p "$CACHE_DIR"
T="$(mktemp -d "$CACHE_DIR/gcpkg-library-ports.XXXXXX")"
trap 'rm -rf "$T"' EXIT

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="${GCPKG_BIN:-$ROOT/build/bin/gcpkg}"
PORTS="$ROOT/ports"
CATALOG="$ROOT/tools/library-catalog.tsv"
NAMES="$(tail -n +2 "$CATALOG" | cut -f1)"
N="$(echo "$NAMES" | wc -w)"

[ -x "$BIN" ] || { echo "build gcpkg first: cmake -S . -B build && cmake --build build -j"; exit 1; }
[ -x "$ROOT/setup-gcpkg-toolchain.sh" ] || { echo "missing setup-gcpkg-toolchain.sh"; exit 1; }
[ "$N" -eq 24 ] || { echo "catalog must have 24 ports, got $N"; exit 1; }
command -v luac >/dev/null 2>&1 || command -v luac5.4 >/dev/null 2>&1 || {
    echo "luac or luac5.4 is required"; exit 1; }
LUAC=luac; command -v luac >/dev/null 2>&1 || LUAC=luac5.4

echo "== catalog / port files / Lua syntax =="
for name in $NAMES; do
    d="$PORTS/$name"
    [ -f "$d/build.lua" ] || { echo "missing $d/build.lua"; exit 1; }
    [ -f "$d/features.yaml" ] || { echo "missing $d/features.yaml"; exit 1; }
    "$LUAC" -p "$d/build.lua"
    grep -Eq 'url = "https://' "$d/build.lua" || { echo "no https URL: $name"; exit 1; }
    grep -Eq 'sha256 = "[0-9a-f]{64}"' "$d/build.lua" || { echo "bad SHA256: $name"; exit 1; }
    grep -Eq 'license_files|share.*doc' "$d/build.lua" || { echo "no license copy: $name"; exit 1; }
    grep -F "port: $name" "$d/features.yaml" > /dev/null
done
python3 - "$ROOT" <<'PY'
import pathlib, subprocess, sys
root = pathlib.Path(sys.argv[1])
home = str(pathlib.Path.home())
skip = {'.git', 'build', '.cache', '.arena', '__pycache__', 'Unselected files'}
if (root / '.git').exists():
    files = subprocess.check_output(
        ['git', 'ls-files', '-z', '--cached', '--others', '--exclude-standard'],
        cwd=root).decode().split('\0')
else:
    files = [str(p.relative_to(root)) for p in root.rglob('*')
             if p.is_file() and not any(part in skip for part in p.relative_to(root).parts)]
for rel in files:
    if not rel:
        continue
    p = root / rel
    try:
        text = p.read_text()
    except (UnicodeDecodeError, OSError):
        continue
    assert home not in text, 'machine-specific path in ' + rel
print(' ', len(files), 'tracked files contain no machine-specific home path')
PY
echo "  $N library ports x (build.lua + features.yaml), real URL/SHA256"

echo "== generator is reproducible =="
HASH1=$(for name in $NAMES; do cat "$PORTS/$name/build.lua" "$PORTS/$name/features.yaml"; done | sha256sum | cut -d' ' -f1)
python3 "$ROOT/tools/gen-library-ports.py" > /dev/null
HASH2=$(for name in $NAMES; do cat "$PORTS/$name/build.lua" "$PORTS/$name/features.yaml"; done | sha256sum | cut -d' ' -f1)
[ "$HASH1" = "$HASH2" ] || { echo "generator is not reproducible"; exit 1; }
echo "  catalog + generator regenerate byte-identical ports"

echo "== registry, global store and Conan CLI surface =="
"$BIN" check --ports "$PORTS" > "$T/check.log" 2>&1
python3 - "$T/check.log" <<'PY'
import re, sys
text = open(sys.argv[1]).read()
m = re.search(r'(\d+) ports OK', text)
assert m and int(m.group(1)) >= 301, text
print(' ', m.group(1), 'ports OK')
PY
"$BIN" --help > "$T/help.log" 2>&1
grep -F 'gcpkg store show' "$T/help.log" > /dev/null
grep -F 'conan,cmake' "$T/help.log" > /dev/null
grep -F '@conan@ / @canon@' "$T/help.log" > /dev/null
export GCPKG_CONFIG="$T/gcpkg-config.yaml"
export XDG_CONFIG_HOME="$T/xdg"
unset GCPKG_HOME GCPKG_STORE || true
"$BIN" store show > "$T/store-default.log" 2>&1
"$BIN" store set "$T/global-store" > "$T/store-set.log" 2>&1
"$BIN" store show > "$T/store-set-show.log" 2>&1
grep -F 'source: default' "$T/store-default.log" > /dev/null
grep -F "$T/global-store" "$T/store-set-show.log" > /dev/null
"$BIN" store unset > "$T/store-unset.log" 2>&1
"$BIN" store show > "$T/store-unset-show.log" 2>&1
grep -F 'persistent: (none)' "$T/store-unset-show.log" > /dev/null
export GCPKG_HOME="$T/home"
echo "  registry >= 301, persistent store show/set/unset and Conan help OK"

if [ "${GCPKG_LIBRARY_PORTS_DYNAMIC:-0}" != "1" ]; then
    echo "  dynamic build disabled; set GCPKG_LIBRARY_PORTS_DYNAMIC=1 to install all libraries"
    echo "library ports test OK (offline)"
    exit 0
fi

echo "== install all 24 libraries from the catalog =="
STORE="${GCPKG_LIBRARY_PORTS_STORE:-$T/store}"
LOGS="$T/logs"
PROJECT="$T/project"
mkdir -p "$STORE" "$LOGS" "$PROJECT"
{
    echo 'schema: 1'
    echo 'project: library-ports'
    echo 'version: 0.1.0'
    echo 'dependencies:'
    for name in $NAMES; do echo "  - $name"; done
} > "$PROJECT/gcpkg.yaml"
timeout 1500 env GCPKG_CONFIG="$GCPKG_CONFIG" XDG_CONFIG_HOME="$XDG_CONFIG_HOME" \
    GCPKG_HOME="$GCPKG_HOME" "$BIN" install -C "$PROJECT" \
    --store "$STORE" --ports "$PORTS" -j 2 > "$LOGS/install.log" 2>&1 || {
        echo "project dependency install failed"; tail -40 "$LOGS/install.log"; exit 1; }

python3 - "$STORE" "$CATALOG" <<'PY'
import csv, json, os, pathlib, sys

store = pathlib.Path(sys.argv[1])
with open(sys.argv[2], newline='') as f:
    rows = list(csv.DictReader(f, delimiter='\t'))
total = 0
for row in rows:
    name, kind = row['name'], row['kind']
    matches = sorted((store / 'manifest').glob(name + '-*.json'))
    assert matches, 'missing manifest for ' + name
    m = json.load(open(matches[-1]))
    entries = int(m.get('compdb_entries') or 0)
    assert entries > 0, 'no compile commands for ' + name
    includes = [m['includes']] if isinstance(m['includes'], str) else list(m['includes'])
    libdirs = [m['libdirs']] if isinstance(m['libdirs'], str) else list(m['libdirs'])
    assert includes and all(os.path.isdir(p) for p in includes), 'bad include dirs: ' + name
    assert libdirs and all(os.path.isdir(p) for p in libdirs), 'bad lib dirs: ' + name
    raw_libs = m.get('libs') or []
    libs = list(raw_libs.values()) if isinstance(raw_libs, dict) else list(raw_libs)
    if kind == 'header':
        assert not libs, 'header-only port exported libraries: ' + name
    else:
        assert libs, 'compiled port exported no libraries: ' + name
        for lib in libs:
            found = any(list(pathlib.Path(d).glob('lib%s.a' % lib)) +
                        list(pathlib.Path(d).glob('lib%s.so*' % lib))
                        for d in libdirs)
            assert found, 'missing lib%s for %s' % (lib, name)
    docs = pathlib.Path(m['prefix']) / 'share' / 'doc' / name
    assert docs.is_dir() and any(docs.iterdir()), 'missing license files for ' + name
    total += entries
    print('  %-18s %-6s compdb=%-5d libs=%d' % (name, kind, entries, len(libs)))
print('  %d ports installed, %d compile commands' % (len(rows), total))
PY
echo "library ports test OK (offline + dynamic: $N/$N ports installed)"
