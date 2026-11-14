#!/usr/bin/env bash
# Static guard against the R20 low-level flags bug: port builds must not
# inject the whole transitive dependency include closure into every compiler.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
PORT=$ROOT/lua/gcpkg/port.lua
R20=$ROOT/lua/gcpkg/r20.lua

grep -F 'function M.dependency_env(ordered, opts)' "$PORT" >/dev/null
grep -F 'local includeFlags = opts.include_flags ~= false' "$PORT" >/dev/null
grep -F 'M.dependency_env(ordered, { include_flags = false, direct_keys = directKeys })' "$PORT" >/dev/null
grep -F 'assertSaneCompilerFlags(childEnv)' "$PORT" >/dev/null
grep -F 'direct_values(ctx, "includes")' "$R20" >/dev/null
grep -F 'direct_values(ctx, "defines")' "$R20" >/dev/null
grep -F 'direct_values(ctx, "libdirs")' "$R20" >/dev/null
if grep -F 'values(ctx.includes)' "$R20" >/dev/null; then
    echo "r20.flags() must not use ctx.includes (transitive include explosion)" >&2
    exit 1
fi
if grep -F 'values(ctx.defines)' "$R20" >/dev/null; then
    echo "r20.flags() must not use ctx.defines (transitive define explosion)" >&2
    exit 1
fi
echo "R20_FLAGS_GUARD_OK"

grep -F 'GCPKG_PKG_CONFIG_INCLUDE_PREFIXES' "$R20" >/dev/null
grep -F 'ctx.env.PKG_CONFIG = wrapper' "$R20" >/dev/null
grep -F '"--cc=" .. ctx.compiler.wrapper_cc' "$ROOT/ports/ffmpeg/build.lua" >/dev/null
grep -F '"--cxx=" .. ctx.compiler.wrapper_cxx' "$ROOT/ports/ffmpeg/build.lua" >/dev/null
grep -F '"--pkg-config=" .. ctx.env.PKG_CONFIG' "$ROOT/ports/ffmpeg/build.lua" >/dev/null

grep -F 'include_flags = false, direct_keys = directKeys' "$PORT" >/dev/null
grep -F 'local directLibdirs, pkgdirs, bins = {}, {}, {}' "$PORT" >/dev/null
grep -F 'env.LIBRARY_PATH = table.concat(util.uniq(directLibdirs), ":")' "$PORT" >/dev/null
grep -F '"LDFLAGS"' "$PORT" >/dev/null
grep -F 'duplicate " .. prefix .. " flag' "$PORT" >/dev/null
grep -F 'net.sha256_cached' "$PORT" >/dev/null
grep -F 'CMAKE_PREFIX_PATH = table.concat(util.uniq(directPrefixes), ";")' "$PORT" >/dev/null
grep -F 'ctx.dependencies or {}' "$ROOT/lua/gcpkg/recipe.lua" >/dev/null
grep -F 'function M.direct_path_list' "$R20" >/dev/null
grep -F 'function M.dep_include_flags' "$R20" >/dev/null
grep -F 'CMAKE_REQUIRED_INCLUDES' "$ROOT/ports/sdl3/build.lua" >/dev/null
if grep -F 'configure-cache' "$ROOT/ports/ffmpeg/build.lua" >/dev/null; then
    echo "configure cache must not be used as a performance fix" >&2
    exit 1
fi
