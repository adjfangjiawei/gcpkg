#!/usr/bin/env bash
# Managed workspaces: the OUTER gcpkg maintains a multi-repository workspace
# (Git, recursive submodules, fixed commits, cross-project tree and order),
# while INNER CMake / GN / Meson / Conan / Makefile stay intact.
# Default: static only.  GCPKG_WORKSPACE_DYNAMIC=1 runs a clean local-Git workspace
# with all inner systems really built (tests/fixtures/managed-workspace/dynamic.sh).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/build/bin/gcpkg"
PORTS="$ROOT/ports"
FIX="$ROOT/tests/fixtures/managed-workspace"
: "${HOME:?HOME must be set}"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}"
mkdir -p "$CACHE_DIR"
T="$(mktemp -d "$CACHE_DIR/gcpkg-managed-static.XXXXXX")"
trap 'rm -rf "$T"' EXIT
[ -x "$BIN" ] || { echo "build gcpkg first: cmake -S $ROOT -B $ROOT/build && cmake --build $ROOT/build -j"; exit 1; }
if command -v luac >/dev/null 2>&1; then LUAC=luac
elif command -v luac5.4 >/dev/null 2>&1; then LUAC=luac5.4
else echo "luac or luac5.4 is required for the static Lua checks"; exit 1
fi
command -v git >/dev/null 2>&1 || { echo "git is required"; exit 1; }

echo "== managed workspace source modules and Lua syntax =="
MODULES=(
    lua/gcpkg/managed.lua lua/gcpkg/git.lua lua/gcpkg/inject.lua
    lua/gcpkg/inner.lua lua/gcpkg/meta.lua lua/gcpkg/detect.lua
    lua/gcpkg/build/auto.lua lua/gcpkg/project.lua
    lua/gcpkg/workspace.lua lua/gcpkg/cli.lua lua/gcpkg/recipe.lua
)
for m in "${MODULES[@]}"; do
    [ -f "$ROOT/$m" ] || { echo "missing $m"; exit 1; }
    "$LUAC" -p "$ROOT/$m"
done
echo "  ${#MODULES[@]} Lua modules parse"
grep -F 'inner_package_manager = "conan"' "$ROOT/lua/gcpkg/inject.lua" > /dev/null
grep -F 'inner_package_manager = "canon"' "$ROOT/lua/gcpkg/inject.lua" > /dev/null
grep -F 'CMAKE_C_STANDARD_LIBRARIES_INIT' "$ROOT/lua/gcpkg/inject.lua" > /dev/null
grep -F 'if(NOT DEFINED ENV{GCPKG_INJECT_DIR})' "$ROOT/lua/gcpkg/inject.lua" > /dev/null
grep -F 'makeValue' "$ROOT/lua/gcpkg/inject.lua" > /dev/null
grep -F 'gn = "gcpkg.build.gn"' "$ROOT/lua/gcpkg/build/auto.lua" > /dev/null
grep -F 'conanfile.py' "$ROOT/lua/gcpkg/detect.lua" > /dev/null
grep -F 'canonfile' "$ROOT/lua/gcpkg/detect.lua" > /dev/null
grep -F 'function M.header' "$ROOT/lua/gcpkg/recipe.lua" > /dev/null
grep -F 'conan_cmd = auto.conan_cmd' "$ROOT/lua/gcpkg/project.lua" > /dev/null
grep -F 'no gcpkg.lua or gcpkg.yaml in ' "$ROOT/lua/gcpkg/project.lua" > /dev/null
grep -F 'project_dir(o), cfg' "$ROOT/lua/gcpkg/cli.lua" > /dev/null
echo "  Conan + canon alias, header recipe, static link order, YAML-only projects and GN detection OK"

echo "== docs and fixtures =="
for f in docs/MANAGED_WORKSPACES.md docs/DEPENDENCY_INJECTION.md docs/CONAN.md \
         tests/fixtures/managed-workspace/README.md \
         tests/fixtures/managed-workspace/dynamic.sh \
         tests/fixtures/managed-workspace/static/workspace.yaml \
         tests/fixtures/managed-workspace/static/repos/app/conanfile.txt \
         tests/fixtures/managed-workspace/static/repos/app/canonfile \
         tests/fixtures/managed-workspace/project/gcpkg.yaml; do
    [ -f "$ROOT/$f" ] || { echo "missing $f"; exit 1; }
done
bash -n "$FIX/dynamic.sh"
grep -Fi 'conan' "$FIX/static/repos/app/conanfile.txt" > /dev/null
grep -F 'canon' "$FIX/static/repos/app/canonfile" > /dev/null
echo "  managed workspace docs, static fixture and dynamic fixture OK"

echo "== registry and CLI surface =="
"$BIN" check --ports "$PORTS" > "$T/check.log" 2>&1
python3 - "$T/check.log" <<'PY'
import re, sys
text = open(sys.argv[1]).read()
m = re.search(r"(\d+) ports OK", text)
assert m and int(m.group(1)) >= 301, text
print("  ", m.group(1), "ports OK")
PY
"$BIN" --help > "$T/help.log" 2>&1
grep -F 'Managed workspaces' "$T/help.log" > /dev/null
grep -F 'gcpkg inject' "$T/help.log" > /dev/null
grep -F 'conan,cmake' "$T/help.log" > /dev/null
grep -F 'workspace submodule' "$T/help.log" > /dev/null
"$BIN" doctor > "$T/doctor.log" 2>&1
grep -F 'compiler interceptor' "$T/doctor.log" > /dev/null
echo "  registry >= 301 ports OK, help/doctor OK"

echo "== static workspace graph and inferred edges =="
"$BIN" workspace graph -C "$FIX/static" --store "$T/store" > "$T/graph.log" 2>&1
grep -Eq '1\. +core +<- \[\]' "$T/graph.log" || { cat "$T/graph.log"; exit 1; }
grep -Eq '2\. +app +<- \[core\]' "$T/graph.log" || { cat "$T/graph.log"; exit 1; }
grep -Eq '3\. +leaf +<- \[app\]' "$T/graph.log" || { cat "$T/graph.log"; exit 1; }
echo "  core -> app -> leaf topological order OK"

echo "== cycle rejection =="
mkdir -p "$T/cycle"
cat > "$T/cycle/workspace.yaml" <<'EOF'
workspace: cycle
repos:
  - name: a
    path: a
    depends: [b]
  - name: b
    path: b
    depends: [a]
EOF
if "$BIN" workspace graph -C "$T/cycle" --store "$T/store" > "$T/cycle.log" 2>&1; then
    echo "cycle was not rejected"; cat "$T/cycle.log"; exit 1
fi
grep -F 'dependency cycle' "$T/cycle.log" > /dev/null
echo "  a -> b -> a is refused"

echo "== workspace.yaml write/read preserves Conan + canon alias =="
cp -a "$FIX/static" "$T/edit"
"$BIN" workspace add -C "$T/edit" --name=tools --path=repos/tools \
    --system=cmake --depends=core --store "$T/store" > "$T/add.log" 2>&1
"$BIN" workspace remove tools -C "$T/edit" --store "$T/store" > "$T/remove.log" 2>&1
grep -F 'systems: ["conan","cmake"]' "$T/edit/workspace.yaml" > /dev/null
grep -F 'conan_cmd:' "$T/edit/workspace.yaml" > /dev/null
grep -F 'canon_cmd:' "$T/edit/workspace.yaml" > /dev/null
grep -F 'conan:' "$T/edit/workspace.yaml" > /dev/null
grep -F 'cmake:' "$T/edit/workspace.yaml" > /dev/null
if grep -F 'name: "tools"' "$T/edit/workspace.yaml" > /dev/null; then
    echo "remove left tools in workspace.yaml"; exit 1
fi
echo "  add/remove keeps systems, conan_cmd, canon_cmd and commands"

echo "== gcpkg.yaml write/read preserves YAML-only inner systems =="
cp -a "$FIX/project" "$T/project"
"$BIN" add zlib -C "$T/project" --ports "$PORTS" --store "$T/store" > "$T/project-add.log" 2>&1
"$BIN" remove zlib -C "$T/project" --ports "$PORTS" --store "$T/store" > "$T/project-remove.log" 2>&1
grep -F 'system: ["conan","cmake"]' "$T/project/gcpkg.yaml" > /dev/null
grep -F 'conan_cmd:' "$T/project/gcpkg.yaml" > /dev/null
grep -F 'canon_cmd:' "$T/project/gcpkg.yaml" > /dev/null
grep -F 'commands:' "$T/project/gcpkg.yaml" > /dev/null
echo "  gcpkg add/remove preserves YAML-only project metadata"

echo "== top-level inject writes a complete vcpkg-style bundle =="
cp -a "$FIX/project" "$T/inject"
"$BIN" inject -C "$T/inject" --install --system=conan,cmake --store "$T/store" \
    --ports "$PORTS" > "$T/inject.log" 2>&1
[ -f "$T/inject/gcpkg.lock" ]
D="$T/inject/.gcpkg/inject"
for f in gcpkg-toolchain.cmake gcpkg-cache.cmake gcpkg-meson.ini \
         gcpkg-gn.gni gcpkg-gn-args.gn gcpkg-flags.mk gcpkg-env.sh \
         gcpkg-conan-env.sh gcpkg-conan.sh gcpkg-canon-env.sh gcpkg-canon.sh \
         gcpkg-deps.json gcpkg-conan.json gcpkg-canon.json; do
    [ -f "$D/$f" ] || { echo "missing injection file $f"; exit 1; }
done
bash -n "$D/gcpkg-env.sh" "$D/gcpkg-conan.sh" "$D/gcpkg-canon.sh"
cmake -P "$D/gcpkg-toolchain.cmake"
cmake -P "$D/gcpkg-cache.cmake"
python3 - "$D" <<'PY'
import json, os, sys
d = sys.argv[1]
generic = json.load(open(os.path.join(d, "gcpkg-deps.json")))
conan = json.load(open(os.path.join(d, "gcpkg-conan.json")))
canon = json.load(open(os.path.join(d, "gcpkg-canon.json")))
for manifest in (generic, conan, canon):
    assert manifest["generator"] == "gcpkg"
assert conan["inner_package_manager"] == "conan"
assert canon["inner_package_manager"] == "canon"
assert "conan" in conan["note"].lower()
assert "conan" in canon["note"].lower()
for key in ("CONAN_ROOT", "CONAN_DEPS_JSON", "CONAN_CMAKE_TOOLCHAIN_FILE",
            "CONAN_LDLIBS", "CANON_ROOT", "CANON_DEPS_JSON"):
    assert key in conan["environment"], key
assert conan["environment"]["CONAN_ROOT"] == conan["environment"]["CANON_ROOT"]
PY
echo "  toolchain/cache/native/gni/flags/env/Conan+canon manifests OK"

if [ "${GCPKG_WORKSPACE_DYNAMIC:-0}" = 1 ]; then
    echo "== clean dynamic managed workspace (local Git, no network) =="
    GCPKG_WORKSPACE_ROOT="$ROOT" GCPKG_WORKSPACE_BIN="$BIN" \
    GCPKG_WORKSPACE_GN_STORE="${GCPKG_WORKSPACE_GN_STORE:-}" \
    GCPKG_WORKSPACE_PROBE_DIR="$T/dynamic" GCPKG_WORKSPACE_KEEP=1 \
        bash "$FIX/dynamic.sh" 2>&1 | tee "$T/dynamic.log"
    grep -F 'managed workspace dynamic OK' "$T/dynamic.log" > /dev/null
    # shellcheck disable=SC1090
    . "$T/dynamic/results.env"
    [ "${REPOS:-0}" -ge 4 ] || { echo "too few dynamic repos: ${REPOS:-0}"; exit 1; }
    [ "${COMPDB:-0}" -ge 5 ] || { echo "too few dynamic compdb entries: ${COMPDB:-0}"; exit 1; }
    echo "  dynamic: ${REPOS} repositories / ${COMPDB} compile commands"
    echo "managed workspace test OK (static + dynamic: ${REPOS}/${REPOS} really built)"
else
    echo "  dynamic build disabled; set GCPKG_WORKSPACE_DYNAMIC=1 to build all inner systems"
    echo "managed workspace test OK (static)"
fi
