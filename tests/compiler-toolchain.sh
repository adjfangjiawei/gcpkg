#!/usr/bin/env bash
# Compiler/toolchain regression: versioned clang discovery, clang-by-default,
# Windows static policy (WSL == Linux), configuration precedence, cross files,
# LLVM external port / installer wiring, wrapper -> compdb and real builds.
set -euo pipefail

: "${HOME:?HOME must be set}"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}"
mkdir -p "$CACHE_DIR"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
BIN="$ROOT/build/bin/gcpkg"
[ -x "$BIN" ] || { echo "build gcpkg first: cmake -S . -B build && cmake --build build -j"; exit 1; }

T="$(mktemp -d "$CACHE_DIR/gcpkg-compiler-toolchain-test.XXXXXX")"
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/home" "$T/fake/bin" "$T/sysroot/usr/lib/pkgconfig" \
         "$T/sysroot/usr/share/pkgconfig" "$T/state" "$T/app-parent" \
         "$T/project" "$T/fakellvm/bin" "$T/llvm-store" \
         "$T/store-native" "$T/store-cross" "$T/project-store" \
         "$T/ports/fixtureclang"
: > "$T/config.yaml"
export GCPKG_CONFIG="$T/config.yaml"
export GCPKG_HOME="$T/home"
unset CC CXX GCPKG_CC GCPKG_CXX GCPKG_TARGET GCPKG_TRIPLE \
      GCPKG_SYSROOT GCPKG_CROSS_PREFIX GCPKG_LLVM_HOME LLVM_HOME LLVM_ROOT \
      GCPKG_ALLOW_GCC_FALLBACK || true

fail() { echo "FAILED: $*" >&2; exit 1; }
has() { grep -F "$1" "$2" >/dev/null; }
now() { python3 -c 'import time; print(time.time())'; }
elapsed() { python3 - "$1" "$2" <<'PY'
import sys
print(f"{float(sys.argv[2]) - float(sys.argv[1]):.2f}s")
PY
}

echo "== static wiring =="
LUAC=""
if command -v luac5.4 >/dev/null 2>&1; then LUAC=luac5.4
elif command -v luac >/dev/null 2>&1; then LUAC=luac
fi
if [ -n "$LUAC" ]; then "$LUAC" -p "$ROOT/tests/fixtures/lua-unit-compiler.lua"; fi
LUA=""
if command -v lua5.4 >/dev/null 2>&1; then LUA=lua5.4
elif command -v lua >/dev/null 2>&1; then LUA=lua
fi
[ -n "$LUA" ] || fail "lua5.4 is needed for the pure-Lua toolchain unit"
GCPKG_LUA_ROOT="$ROOT" GCPKG_FAKE_OS=linux \
  GCPKG_TEST_SYSROOT="$T/sysroot" GCPKG_TEST_STATE="$T/state" \
  "$LUA" "$ROOT/tests/fixtures/lua-unit-compiler.lua" > "$T/unit.out"
has "compiler/toolchain Lua unit OK" "$T/unit.out"

grep -F 'gcpkg.sys.compiler = toolchain.compiler' "$ROOT/lua/main.lua" >/dev/null
grep -F 'toolchain.fingerprint()' "$ROOT/lua/gcpkg/port.lua" >/dev/null
grep -F 'GCPKG_COMPILER_FLAGS' "$ROOT/Source/Intercept/InterceptMain.cpp" >/dev/null
grep -F 'real = cxx ? "clang++" : "clang";' "$ROOT/Source/Intercept/InterceptMain.cpp" >/dev/null
grep -F 'fallback = cxx ? "clang++" : "clang";' "$ROOT/Source/Core/Engine.cpp" >/dev/null
grep -F 'toolchain.cmake_args' "$ROOT/lua/gcpkg/build/cmake.lua" >/dev/null
grep -F 'toolchain.meson_args' "$ROOT/lua/gcpkg/build/meson.lua" >/dev/null
grep -F 'toolchain.autotools_args' "$ROOT/lua/gcpkg/build/autotools.lua" >/dev/null
grep -F 'toolchain.flags()' "$ROOT/lua/gcpkg/build/cc.lua" >/dev/null
grep -F 'gcpkg-cross.ini' "$ROOT/lua/gcpkg/inject.lua" >/dev/null
grep -F 'external.declare' "$ROOT/ports/llvm/build.lua" >/dev/null
grep -F 'https://apt.llvm.org/llvm.sh' "$ROOT/ports/llvm/build.lua" >/dev/null
grep -F 'wget https://apt.llvm.org/llvm.sh' "$ROOT/tools/llvm-install.sh" >/dev/null
[ -f "$ROOT/ports/llvm/features.yaml" ] || fail "ports/llvm/features.yaml missing"
echo "  static wiring + pure-Lua Windows/WSL/cross unit OK"

echo "== versioned clang is the default; gcc/MSVC env defaults are ignored =="
for name in clang clang++ clang-22 clang++-22 clang-23 clang++-23 \
            clang-cl-23 clang-cpp-23 gcc g++ cl.exe cl; do
    printf '#!/bin/sh\nexit 0\n' > "$T/fake/bin/$name"
    chmod +x "$T/fake/bin/$name"
done
FAKE_PATH="$T/fake/bin:$PATH"
for cc in cl.exe gcc; do
    env -u GCPKG_CC -u GCPKG_CXX -u GCPKG_TARGET -u GCPKG_SYSROOT \
        CC="$cc" CXX="$cc" PATH="$FAKE_PATH" \
        "$BIN" toolchain --ports "$ROOT/ports" > "$T/default-$cc.out" 2>&1
    grep -E '^\[gcpkg:info\] +cc +: ' "$T/default-$cc.out" | grep -F 'clang-23' >/dev/null ||
        fail "cc default was not versioned clang-23 with CC=$cc"
    grep -E '^\[gcpkg:info\] +cxx +: ' "$T/default-$cc.out" | grep -F 'clang++-23' >/dev/null ||
        fail "cxx default was not versioned clang++-23 with CXX=$cc"
    if grep -E '^\[gcpkg:info\] +c(c|x) +: .*(gcc|g\+\+|cl\.exe|MSVC)' "$T/default-$cc.out" >/dev/null; then
        fail "gcc/MSVC leaked into compiler selection with CC=$cc"
    fi
done
has 'clang (never gcc/MSVC); WSL == linux' "$T/default-cl.exe.out"
has '[clang-23]' "$T/default-cl.exe.out"
echo "  clang-23/clang++-23 selected; CC=cl.exe and CC=gcc ignored"

echo "== versioned clang-cl / clang-cpp pairing =="
mkdir -p "$T/clangcl/bin"
for name in clang-cl-99 clang-cpp-99; do
    printf '#!/bin/sh\nexit 0\n' > "$T/clangcl/bin/$name"
    chmod +x "$T/clangcl/bin/$name"
done
env -u CC -u CXX -u GCPKG_CC -u GCPKG_CXX -u GCPKG_TARGET \
    -u GCPKG_SYSROOT GCPKG_CONFIG="$T/config.yaml" \
    PATH="$T/clangcl/bin:$PATH" "$BIN" toolchain --ports "$ROOT/ports" \
    > "$T/clangcl.out" 2>&1
grep -E '^\[gcpkg:info\] +cc +: ' "$T/clangcl.out" |
    grep -F 'clang-cl-99' >/dev/null ||
    fail "clang-cl-99 was not selected as the versioned C driver"
grep -E '^\[gcpkg:info\] +cxx +: ' "$T/clangcl.out" |
    grep -F 'clang-cpp-99' >/dev/null ||
    fail "clang-cpp-99 was not paired as the versioned C++ driver"
echo "  clang-cl-99 / clang-cpp-99 versioned pair OK"

echo "== configuration precedence: CLI > project > user > env =="
cat > "$T/user.yaml" <<EOF
store: "$T/home"
compiler:
  cc: "/user/clang"
  cxx: "/user/clang++"
  target: "x86_64-linux-gnu"
  llvm_home: "/user/llvm"
EOF
cat > "$T/project/gcpkg.yaml" <<EOF
schema: 1
project: demo
dependencies: []
compiler:
  cc: "/project/clang"
  cxx: "/project/clang++"
EOF
: > "$T/empty.yaml"
env GCPKG_CONFIG="$T/empty.yaml" GCPKG_CC=/env/clang GCPKG_CXX=/env/clang++ \
    "$BIN" toolchain --ports "$ROOT/ports" > "$T/priority-env.out" 2>&1
grep -E '^\[gcpkg:info\] +cc +: ' "$T/priority-env.out" | grep -F '/env/clang' >/dev/null ||
    fail "GCPKG_CC did not win over auto detection"
env GCPKG_CONFIG="$T/empty.yaml" CC=/env/cc-clang CXX=/env/cxx-clang++ \
    "$BIN" toolchain --ports "$ROOT/ports" > "$T/priority-cc.out" 2>&1
grep -E '^\[gcpkg:info\] +cc +: ' "$T/priority-cc.out" |
    grep -F '/env/cc-clang' >/dev/null ||
    fail "explicit non-default CC was not honored at env priority"
env GCPKG_CONFIG="$T/user.yaml" GCPKG_CC=/env/clang GCPKG_CXX=/env/clang++ \
    "$BIN" toolchain --ports "$ROOT/ports" > "$T/priority-user.out" 2>&1
grep -E '^\[gcpkg:info\] +cc +: ' "$T/priority-user.out" | grep -F '/user/clang' >/dev/null ||
    fail "user config did not win over env"
env GCPKG_CONFIG="$T/user.yaml" GCPKG_CC=/env/clang GCPKG_CXX=/env/clang++ \
    "$BIN" toolchain -C "$T/project" --ports "$ROOT/ports" > "$T/priority-project.out" 2>&1
grep -E '^\[gcpkg:info\] +cc +: ' "$T/priority-project.out" | grep -F '/project/clang' >/dev/null ||
    fail "project config did not win over user/env"
env GCPKG_CONFIG="$T/user.yaml" GCPKG_CC=/env/clang GCPKG_CXX=/env/clang++ \
    "$BIN" toolchain -C "$T/project" --ports "$ROOT/ports" \
    --cc=/cli/clang --cxx=/cli/clang++ > "$T/priority-cli.out" 2>&1
grep -E '^\[gcpkg:info\] +cc +: ' "$T/priority-cli.out" | grep -F '/cli/clang' >/dev/null ||
    fail "CLI did not win over project"
echo "  CLI > project > user > env OK"

echo "== cross target: CMake toolchain + Meson cross file + sysroot =="
env GCPKG_CONFIG="$T/empty.yaml" \
    "$BIN" toolchain --target=aarch64-linux-gnu --sysroot="$T/sysroot" \
    --cross-prefix=aarch64-linux-gnu- --ports "$ROOT/ports" \
    > "$T/cross.out" 2>&1
grep -E 'target +: aarch64-linux-gnu' "$T/cross.out" >/dev/null
grep -E 'cross +: yes' "$T/cross.out" >/dev/null
grep -E 'compiler flags +: --target=aarch64-linux-gnu' "$T/cross.out" >/dev/null
CMAKE_FILE="$(sed -n 's/.*cmake toolchain *: //p' "$T/cross.out" | head -n1)"
MESON_FILE="$(sed -n 's/.*meson cross file *: //p' "$T/cross.out" | head -n1)"
[ -n "$CMAKE_FILE" ] && [ -f "$CMAKE_FILE" ] || fail "CMake cross toolchain not generated"
[ -n "$MESON_FILE" ] && [ -f "$MESON_FILE" ] || fail "Meson cross file not generated"
grep -F 'set(CMAKE_SYSTEM_NAME "Linux")' "$CMAKE_FILE" >/dev/null
grep -F 'set(CMAKE_SYSTEM_PROCESSOR "aarch64")' "$CMAKE_FILE" >/dev/null
grep -F 'set(CMAKE_C_COMPILER_TARGET "aarch64-linux-gnu")' "$CMAKE_FILE" >/dev/null
grep -F -- '--target=aarch64-linux-gnu' "$CMAKE_FILE" >/dev/null
grep -F -- "--sysroot=$T/sysroot" "$CMAKE_FILE" >/dev/null
grep -F 'system = '\''linux'\''' "$MESON_FILE" >/dev/null
grep -F 'cpu_family = '\''aarch64'\''' "$MESON_FILE" >/dev/null
grep -F 'ar = '\''aarch64-linux-gnu-ar'\''' "$MESON_FILE" >/dev/null
echo "  CMake toolchain + Meson cross file + sysroot OK"

echo "== injected cross toolchain keeps dependency flags and wrapper =="
mkdir -p "$T/inject-store"
"$BIN" new "$T/inject-cross" --name=injectcross --ports "$ROOT/ports" \
    > "$T/inject-new.out" 2>&1
env GCPKG_CONFIG="$T/empty.yaml" \
    "$BIN" inject -C "$T/inject-cross" --install --ports "$ROOT/ports" \
    --store "$T/inject-store" --target=aarch64-linux-gnu \
    --sysroot="$T/sysroot" --cc=/opt/llvm-23/bin/clang-23 \
    --cxx=/opt/llvm-23/bin/clang++-23 > "$T/inject-cross.out" 2>&1
INJECT_DIR="$T/inject-cross/.gcpkg/inject"
INJECT_CMAKE="$INJECT_DIR/gcpkg-toolchain.cmake"
INJECT_ENV="$INJECT_DIR/gcpkg-env.sh"
INJECT_MESON="$INJECT_DIR/gcpkg-cross.ini"
STORE_CMAKE="$T/inject-store/toolchain-aarch64-linux-gnu.cmake"
for f in "$INJECT_CMAKE" "$INJECT_ENV" "$INJECT_MESON" "$STORE_CMAKE"; do
    [ -f "$f" ] || fail "missing injected cross file: $f"
done
FLAG_INIT_COUNT="$(grep -c '^ *set(CMAKE_C_FLAGS_INIT' "$INJECT_CMAKE" || true)"
[ "$FLAG_INIT_COUNT" = 1 ] ||
    fail "injection CMAKE_C_FLAGS_INIT was overwritten by cross settings"
has 'set(CMAKE_C_FLAGS_INIT "--target=aarch64-linux-gnu --sysroot=' "$INJECT_CMAKE"
has "list(APPEND CMAKE_FIND_ROOT_PATH \"$T/sysroot\")" "$INJECT_CMAKE"
if grep -F 'set(CMAKE_FIND_ROOT_PATH "' "$INJECT_CMAKE" >/dev/null; then
    fail "cross sysroot replaced dependency CMAKE_FIND_ROOT_PATH"
fi
has 'if(NOT "$ENV{CC}" STREQUAL "" AND NOT "$ENV{GCPKG_CC_REAL}" STREQUAL "")' \
    "$INJECT_CMAKE"
has 'set(CMAKE_C_COMPILER "/opt/llvm-23/bin/clang-23")' "$INJECT_CMAKE"
has 'set(CMAKE_C_COMPILER_TARGET "aarch64-linux-gnu")' "$INJECT_CMAKE"
has "GCPKG_CMAKE_CROSS_FILE='$STORE_CMAKE'" "$INJECT_ENV"
has "GCPKG_COMPILER_FLAGS='--target=aarch64-linux-gnu" "$INJECT_ENV"
has '[host_machine]' "$INJECT_MESON"
has 'set(CMAKE_C_COMPILER "$ENV{CC}")' "$STORE_CMAKE"
echo "  injected CMake flags + wrapper + cross env OK"

echo "== registry / LLVM external port / official installer wiring =="
"$BIN" check --ports "$ROOT/ports" > "$T/check.out" 2>&1
has '316 ports OK' "$T/check.out"
"$BIN" externals --ports "$ROOT/ports" > "$T/externals.out" 2>&1
grep -E '^\[gcpkg:info\] +llvm +GCPKG_LLVM_HOME' "$T/externals.out" >/dev/null ||
    fail "llvm is not listed as an external SDK"
has 'https://apt.llvm.org/llvm.sh' "$T/externals.out"
"$BIN" llvm show --ports "$ROOT/ports" > "$T/llvm-show.out" 2>&1
has 'LLVM binary toolchain (no source build)' "$T/llvm-show.out"
has 'wget https://apt.llvm.org/llvm.sh' "$T/llvm-show.out"
"$BIN" llvm install 23 --dry-run --ports "$ROOT/ports" > "$T/llvm-install.out" 2>&1
has 'wget https://apt.llvm.org/llvm.sh' "$T/llvm-install.out"
has './llvm.sh 23' "$T/llvm-install.out"
has "$ROOT/tools/llvm-install.sh" "$T/llvm-install.out"
env GCPKG_CONFIG="$T/config.yaml" "$BIN" llvm use "$T/fakellvm" > "$T/llvm-use.out" 2>&1
has 'llvm_home: ' "$T/config.yaml"
has "$T/fakellvm" "$T/config.yaml"
env GCPKG_CONFIG="$T/config.yaml" "$BIN" toolchain --ports "$ROOT/ports" > "$T/llvm-selected.out" 2>&1
grep -E 'llvm home +: ' "$T/llvm-selected.out" | grep -F "$T/fakellvm" >/dev/null ||
    fail "gcpkg llvm use did not reach toolchain selection"
env GCPKG_CONFIG="$T/config.yaml" "$BIN" llvm unset > "$T/llvm-unset.out" 2>&1
if has 'llvm_home' "$T/config.yaml"; then fail "llvm unset left llvm_home behind"; fi
cat > "$T/preserve.yaml" <<EOF
# keep me
store: "$T/home"
proxy: "http://127.0.0.1:1"
compiler:
  cc: "/old/clang"
  cxx: "/old/clang++"
# trailing top-level comment
EOF
env GCPKG_CONFIG="$T/preserve.yaml" "$BIN" llvm use "$T/fakellvm" \
    > "$T/llvm-preserve-use.out" 2>&1
has '# keep me' "$T/preserve.yaml"
has 'store: ' "$T/preserve.yaml"
has 'proxy: ' "$T/preserve.yaml"
has '/old/clang' "$T/preserve.yaml"
has 'llvm_home: ' "$T/preserve.yaml"
env GCPKG_CONFIG="$T/preserve.yaml" "$BIN" llvm unset \
    > "$T/llvm-preserve-unset.out" 2>&1
if has 'llvm_home' "$T/preserve.yaml"; then
    fail "llvm unset did not remove only the llvm_home key"
fi
has '# keep me' "$T/preserve.yaml"
has 'store: ' "$T/preserve.yaml"
has 'proxy: ' "$T/preserve.yaml"
has '/old/clang' "$T/preserve.yaml"
echo "  316 ports, LLVM port + installer + use/unset OK"

echo "== real LLVM external port install =="
if [ -d /usr/lib/llvm-22 ]; then
    env GCPKG_CONFIG="$T/empty.yaml" \
        "$BIN" install llvm --ports "$ROOT/ports" --store "$T/llvm-store" \
        --no-cache > "$T/llvm-real.out" 2>&1
    has 'installed llvm-system' "$T/llvm-real.out"
    MANIFEST="$T/llvm-store/manifest/llvm-system.json"
    [ -f "$MANIFEST" ] || fail "llvm manifest missing"
    python3 - "$MANIFEST" <<'PY'
import json, sys
m = json.load(open(sys.argv[1]))
bins = m.get("binaries", [])
assert any("/bin" in b and "llvm-" in b for b in bins), bins
print("  llvm manifest binaries:", ", ".join(bins))
PY
else
    echo "  LLVM root not present; external port install skipped"
fi

echo "== real clang build through intercept wrapper / compdb =="
CLANGXX="$(ls /usr/bin/clang++-* 2>/dev/null | sort -V | tail -n1 || true)"
CLANG=""
if [ -n "$CLANGXX" ] && [ -x "$CLANGXX" ]; then
    CLANG="${CLANGXX/clang++/clang}"
fi
cat > "$T/ports/fixtureclang/build.lua" <<'EOF'
local recipe = require("gcpkg.recipe")
local fs = require("gcpkg.fs")
local util = require("gcpkg.util")
return recipe.make {
    name = "fixtureclang",
    version = "1.0.0",
    source = function(o)
        fs.write(util.join(o.dir, "hello.c"),
                 "int fixture(void) { return 42; }\n")
        fs.write(util.join(o.dir, "Makefile"), table.concat({
            "all:",
            "\t$(CC) $(CFLAGS) -c hello.c -o hello.o",
            "install:",
            "\tmkdir -p \"$(PREFIX)/lib\"",
            "\tcp hello.o \"$(PREFIX)/lib/\"",
        }, "\n") .. "\n")
    end,
    make = {
        vars = function(ctx) return { PREFIX = ctx.prefix } end,
        install_target = "install",
    },
    exports = { libdirs = { "@PREFIX@/lib" } },
}
EOF
cat > "$T/ports/fixtureclang/features.yaml" <<'EOF'
schema: 1
port: fixtureclang
features: {}
EOF

if [ -n "$CLANG" ] && [ -x "$CLANG" ] && [ -x "$CLANGXX" ] && command -v make >/dev/null 2>&1; then
    START="$(now)"
    env GCPKG_CONFIG="$T/empty.yaml" CC=gcc CXX=g++ \
        "$BIN" install fixtureclang --ports "$T/ports" \
        --store "$T/store-native" --cc="$CLANG" --cxx="$CLANGXX" \
        --no-cache > "$T/native-build.out" 2>&1
    END="$(now)"
    has 'toolchain:' "$T/native-build.out"
    has 'compiled in' "$T/native-build.out"
    JSONL="$(find "$T/store-native" -name '*.jsonl' | head -n1)"
    [ -n "$JSONL" ] && has "$CLANG" "$JSONL" || fail "wrapper did not forward $CLANG"
    if grep -E '"(cc|gcc|g\+\+|c\+\+)"' "$JSONL" >/dev/null; then
        fail "gcc/cc leaked into intercepted compile command"
    fi
    COMPDB="$T/store-native/compdb/fixtureclang-1.0.0.json"
    [ -f "$COMPDB" ] || fail "port compile_commands.json missing"
    python3 - "$COMPDB" "$CLANG" <<'PY'
import json, sys
entries = json.load(open(sys.argv[1]))
clang = sys.argv[2]
assert entries, "empty compdb"
assert any(clang in " ".join(e.get("arguments", [])) for e in entries), entries
assert not any(e.get("arguments", [""])[0] in ("cc", "gcc", "g++", "c++") for e in entries)
print("  compdb entries:", len(entries))
PY
    echo "  native $CLANG wrapper + compdb: $(elapsed "$START" "$END")"

    START="$(now)"
    env GCPKG_CONFIG="$T/empty.yaml" CC=gcc CXX=g++ \
        "$BIN" install fixtureclang --ports "$T/ports" \
        --store "$T/store-cross" --target=aarch64-linux-gnu \
        --cc="$CLANG" --cxx="$CLANGXX" --no-cache > "$T/cross-build.out" 2>&1
    END="$(now)"
    grep -E 'cross +: yes' "$T/cross-build.out" >/dev/null
    grep -E 'cmake toolchain *: ' "$T/cross-build.out" >/dev/null
    grep -E 'meson cross file *: ' "$T/cross-build.out" >/dev/null
    has 'compiled in' "$T/cross-build.out"
    XJSONL="$(find "$T/store-cross" -name '*.jsonl' | head -n1)"
    [ -n "$XJSONL" ] || fail "cross build produced no intercept JSONL"
    has "$CLANG" "$XJSONL"
    grep -F -- '--target=aarch64-linux-gnu' "$XJSONL" >/dev/null ||
        fail "cross target missing from intercepted compile command"
    XCOMPDB="$T/store-cross/compdb/fixtureclang-1.0.0.json"
    [ -f "$XCOMPDB" ] || fail "cross compdb missing"
    python3 - "$XCOMPDB" <<'PY'
import json, sys
entries = json.load(open(sys.argv[1]))
assert any(any(a == "--target=aarch64-linux-gnu" for a in e.get("arguments", []))
           for e in entries), entries
print("  cross compdb entries:", len(entries))
PY
    echo "  cross --target=aarch64-linux-gnu wrapper + compdb: $(elapsed "$START" "$END")"

    echo "== real project build with explicit clang and duration =="
    "$BIN" new "$T/app" --name=app --ports "$ROOT/ports" > "$T/new.out" 2>&1
    START="$(now)"
    env GCPKG_CONFIG="$T/empty.yaml" CC=gcc CXX=g++ \
        "$BIN" build "$T/app" --ports "$ROOT/ports" --store "$T/project-store" \
        --cc="$CLANG" --cxx="$CLANGXX" --no-cache > "$T/project-build.out" 2>&1
    END="$(now)"
    has 'toolchain:' "$T/project-build.out"
    has 'compiled in' "$T/project-build.out"
    PROJECT_LOG="$T/app/.gcpkg/logs/project.log"
    [ -f "$PROJECT_LOG" ] || fail "project build log missing"
    grep -F "$CLANG -c" "$PROJECT_LOG" >/dev/null ||
        fail "project compile command did not use $CLANG"
    PCOMPDB="$(find "$T/app" -name compile_commands.json | head -n1)"
    [ -n "$PCOMPDB" ] || fail "project compile_commands.json missing"
    python3 - "$PCOMPDB" "$CLANG" <<'PY'
import json, sys
entries = json.load(open(sys.argv[1]))
clang = sys.argv[2]
assert any(clang in " ".join(e.get("arguments", [])) for e in entries), entries
assert not any(e.get("arguments", [""])[0] in ("cc", "gcc", "g++", "c++") for e in entries)
print("  project compdb entries:", len(entries))
PY
    APP="$(find "$T/app/.gcpkg" -type f -name app -perm -u+x | head -n1 || true)"
    [ -n "$APP" ] || fail "project binary missing"
    "$APP" > "$T/app-run.out" 2>&1
    has 'hello from app' "$T/app-run.out"
    echo "  project $CLANG build + binary: $(elapsed "$START" "$END")"
else
    echo "  versioned clang++ or make missing; real compile smoke skipped"
fi

echo "compiler/toolchain regression PASS"
