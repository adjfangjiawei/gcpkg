#!/usr/bin/env bash
# Regressions for explicit proxy forcing, credential-safe diagnostics and
# CMake 4 policy compatibility. All network activity is local.
set -euo pipefail

: "${HOME:?HOME must be set}"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}"
mkdir -p "$CACHE_DIR"
cd "$(dirname "$0")/.."
ROOT=$(pwd)
BIN="$ROOT/build/bin/gcpkg"
T=$(mktemp -d "$CACHE_DIR/gcpkg-user-regressions.XXXXXX")
cleanup() { rm -rf "$T"; }
trap cleanup EXIT

ok() { echo "  ok: $1"; }
fail() { echo "USER REGRESSION FAILED: $1" >&2; exit 1; }
has() { grep -Fq -- "$2" "$1" || fail "expected '$2' in $1"; }
hasnt() { ! grep -Fq -- "$2" "$1" || fail "unexpected '$2' in $1"; }

[ -x "$BIN" ] || fail "build gcpkg first: cmake -S . -B build && cmake --build build -j"
LUA=lua5.4
command -v "$LUA" >/dev/null 2>&1 || LUA=lua
command -v "$LUA" >/dev/null 2>&1 || fail "lua5.4 or lua is required"
LUAC=luac
command -v "$LUAC" >/dev/null 2>&1 || LUAC=luac5.4
command -v "$LUAC" >/dev/null 2>&1 || fail "luac or luac5.4 is required"

echo "== static: syntax, engine wiring and user documentation =="
for f in lua/gcpkg/proxy.lua lua/gcpkg/net.lua lua/gcpkg/cmake_version.lua \
         lua/gcpkg/build/cmake.lua lua/gcpkg/inject.lua lua/gcpkg/cli.lua \
         tests/fixtures/lua-unit-cmake.lua tests/fixtures/lua-unit-proxy.lua; do
    "$LUAC" -p "$ROOT/$f"
done
has "$ROOT/lua/gcpkg/proxy.lua" "function M.check"
has "$ROOT/lua/gcpkg/net.lua" "proxy.assert_reachable"
has "$ROOT/lua/gcpkg/net.lua" '"-q"'
has "$ROOT/lua/gcpkg/net.lua" "GCPKG_CURL_CONFIG"
has "$ROOT/lua/gcpkg/proxy.lua" "CURL_HOME"
has "$ROOT/lua/gcpkg/proxy.lua" "GIT_CONFIG_COUNT"
has "$ROOT/lua/gcpkg/build/cmake.lua" "dedup_defines"
has "$ROOT/lua/gcpkg/build/cmake.lua" "CMAKE_POLICY_VERSION_MINIMUM"
has "$ROOT/lua/gcpkg/cmake_version.lua" "policy_env"
has "$ROOT/lua/gcpkg/inject.lua" "CMAKE_POLICY_VERSION_MINIMUM"
has "$ROOT/lua/gcpkg/cli.lua" "gcpkg proxy --check"
has "$ROOT/docs/PROXY.md" "gcpkg proxy --check"
has "$ROOT/docs/PROXY.md" "-q -K"
has "$ROOT/docs/TROUBLESHOOTING.md" "CMAKE_POLICY_VERSION_MINIMUM=3.5"
has "$ROOT/docs/BUILD_SYSTEMS.md" "CMAKE_POLICY_VERSION_MINIMUM"
hasnt "$ROOT/lua/gcpkg/proxy.lua" "GCPKG_WSL_HOST"
hasnt "$ROOT/docs/PROXY.md" "Allow LAN"
if grep -Fq 'ZLIB_BUILD_EXAMPLES' "$ROOT/ports/zlib/build.lua"; then
    fail "zlib still has a redundant hard-coded define"
fi
"$BIN" --help > "$T/help.log" 2>&1
has "$T/help.log" "gcpkg proxy --check"
ok "Lua syntax, source wiring and docs"

echo "== unit: CMake adapter and proxy resolver =="
GCPKG_LUA_ROOT="$ROOT/lua" "$LUA" "$ROOT/tests/fixtures/lua-unit-cmake.lua" \
    > "$T/cmake-unit.log" 2>&1 || { tail -20 "$T/cmake-unit.log"; fail "cmake adapter unit"; }
has "$T/cmake-unit.log" "cmake adapter unit OK"
GCPKG_LUA_ROOT="$ROOT/lua" "$LUA" "$ROOT/tests/fixtures/lua-unit-proxy.lua" \
    > "$T/proxy-unit.log" 2>&1 || { tail -20 "$T/proxy-unit.log"; fail "proxy resolver unit"; }
has "$T/proxy-unit.log" "proxy unit OK"
ok "CMake 4 policy, dedup, explicit proxy forcing, redaction"

# A deterministic process environment: no inherited proxy/store config.
mkdir -p "$T/home-user" "$T/fakebin"
export HOME="$T/home-user"
export GCPKG_CONFIG="$T/gcpkg-config.yaml"
export XDG_CONFIG_HOME="$T/xdg"
export PATH="$T/fakebin:$PATH"
unset GCPKG_PROXY GCPKG_NO_PROXY GCPKG_STORE GCPKG_PORTS GCPKG_PROXY_CHECK || true
unset HTTPS_PROXY https_proxy HTTP_PROXY http_proxy ALL_PROXY all_proxy || true
unset CMAKE_POLICY_VERSION_MINIMUM || true
export NO_PROXY='*' no_proxy='*'

# Fake CMake 4: require the policy arg/env and exactly one repeated define.
cat > "$T/fakebin/cmake" <<'SH_CMAKE'
#!/usr/bin/env bash
if [ "${1:-}" = "--version" ]; then
    echo "cmake version 4.0.0"
    exit 0
fi
if [ "${1:-}" = "-S" ]; then
    printf '%s\n' "$*" >> "$GCPKG_TEST_CMAKE_LOG"
    printf 'policy_env=%s\n' "${CMAKE_POLICY_VERSION_MINIMUM:-}" >> "$GCPKG_TEST_CMAKE_LOG"
    case " $* " in
        *" -DCMAKE_POLICY_VERSION_MINIMUM=3.5 "*) ;;
        *) echo "missing CMake 4 policy arg" >&2; exit 1 ;;
    esac
    n=$(printf '%s' "$*" | grep -o -F -- '-DZLIB_BUILD_EXAMPLES=OFF' | wc -l)
    if [ "$n" -ne 1 ]; then
        echo "expected exactly one -DZLIB_BUILD_EXAMPLES=OFF, got $n" >&2
        exit 1
    fi
    if [ "${CMAKE_POLICY_VERSION_MINIMUM:-}" != "3.5" ]; then
        echo "missing CMAKE_POLICY_VERSION_MINIMUM=3.5 in env" >&2
        exit 1
    fi
    build=""
    prev=""
    for a in "$@"; do
        if [ "$prev" = "-B" ]; then build="$a"; break; fi
        prev="$a"
    done
    if [ -z "$build" ]; then echo "missing -B build dir" >&2; exit 1; fi
    mkdir -p "$build"
    printf '[]\n' > "$build/compile_commands.json"
fi
exit 0
SH_CMAKE
chmod +x "$T/fakebin/cmake"

echo "== dynamic: CMake 4 compatibility and generic -D de-duplication =="
mkdir -p "$T/cmake-src" "$T/cmake-ports/cmakepolicyprobe"
printf 'cmake_minimum_required(VERSION 2.8)\nproject(cmakepolicyprobe C)\n' \
    > "$T/cmake-src/CMakeLists.txt"
cat > "$T/cmake-ports/cmakepolicyprobe/build.lua" <<'LUA_PORT'
return {
    name = "cmakepolicyprobe", version = "1.0.0",
    source = { dir = gcpkg.sys.getenv("GCPKG_TEST_SRC") },
    dependencies = {},
    build = function(ctx)
        local cmake = require("gcpkg.build.cmake")
        return cmake.all {
            src = ctx.src, build_dir = ctx.build_dir, prefix = ctx.prefix,
            exec = ctx.exec, log = ctx.log, jobs = ctx.jobs, env = ctx.env,
            defines = { ZLIB_BUILD_EXAMPLES = "OFF" },
            args = { "-DZLIB_BUILD_EXAMPLES=OFF" },
        }
    end,
}
LUA_PORT
cat > "$T/cmake-ports/cmakepolicyprobe/features.yaml" <<'YAML_PORT'
schema: 1
port: cmakepolicyprobe
features: {}
versions: {}
YAML_PORT
GCPKG_HOME="$T/home-cmake" GCPKG_TEST_SRC="$T/cmake-src" \
GCPKG_TEST_CMAKE_LOG="$T/cmake.log" \
    "$BIN" --ports "$T/cmake-ports" --store "$T/store-cmake" \
    install cmakepolicyprobe -j 2 > "$T/cmake-install.log" 2>&1 ||
    fail "CMake policy port failed: $(tail -12 "$T/cmake-install.log" | tr '\n' ' ')"
has "$T/cmake-install.log" "installed cmakepolicyprobe"
has "$T/cmake.log" "-DCMAKE_POLICY_VERSION_MINIMUM=3.5"
has "$T/cmake.log" "policy_env=3.5"
python3 - "$T/cmake.log" <<'PY_ARG'
import sys
text = open(sys.argv[1]).read()
assert text.count("-DCMAKE_POLICY_VERSION_MINIMUM=3.5") == 1, text
assert text.count("-DZLIB_BUILD_EXAMPLES=OFF") == 1, text
print(" ", "one policy define and one de-duplicated feature define")
PY_ARG
ok "CMake 4 configure/build/install inherit policy, no repeated -D"

echo "user regressions OK (static + unit + CMake 4 integration)"
