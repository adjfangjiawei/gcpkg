-- Helpers for the R20 source-only port batch.
-- No host paths, no system -dev packages and no credentials live here.
local util = require("gcpkg.util")
local fs = require("gcpkg.fs")
local M = {}

function M.dep_prefix(ctx, name)
    local m = ctx.dep(name)
    assert(m and m.prefix, "missing dependency prefix: " .. tostring(name))
    return m.prefix
end

function M.dep_include(ctx, name, sub)
    local p = M.dep_prefix(ctx, name)
    return sub and util.join(p, "include", sub) or util.join(p, "include")
end

function M.lib_file(ctx, name, lib)
    local m = ctx.dep(name)
    assert(m, "missing dependency: " .. tostring(name))
    for _, d in ipairs(m.libdirs or {}) do
        for _, f in ipairs({ "lib" .. lib .. ".a", "lib" .. lib .. ".so" }) do
            local p = util.join(d, f)
            if fs.isfile(p) then return p end
        end
    end
    error("missing lib" .. lib .. " for dependency " .. tostring(name))
end

function M.direct_prefixes(ctx)
    local out = {}
    for _, m in ipairs(ctx.dependencies or {}) do
        if m.prefix then out[#out + 1] = m.prefix end
    end
    return util.uniq(out)
end

function M.all_prefixes(ctx)
    local out = {}
    for _, m in ipairs(ctx.all_dependencies or {}) do
        if m.prefix then out[#out + 1] = m.prefix end
    end
    return util.uniq(out)
end

function M.cmake_prefix(ctx)
    return table.concat(M.direct_prefixes(ctx), ";")
end

function M.all_cmake_prefix(ctx)
    return table.concat(M.all_prefixes(ctx), ";")
end

function M.direct_path_list(ctx, field)
    local out = {}
    for _, m in ipairs(ctx.dependencies or {}) do
        for _, p in ipairs(m[field] or {}) do out[#out + 1] = p end
    end
    return table.concat(util.uniq(out), ";")
end

function M.path_list(ctx, field)
    return M.direct_path_list(ctx, field)
end

function M.all_path_list(ctx, field)
    local out = {}
    for _, m in ipairs(ctx.all_dependencies or {}) do
        for _, p in ipairs(m[field] or {}) do out[#out + 1] = p end
    end
    return table.concat(util.uniq(out), ";")
end

function M.dep_include_flags(ctx, name)
    local m = ctx.dep(name)
    assert(m, "missing dependency: " .. tostring(name))
    local out = {}
    for _, p in ipairs(m.includes or {}) do out[#out + 1] = "-I" .. p end
    return table.concat(out, " ")
end

-- CMAKE_REQUIRED_INCLUDES is a CMake list of directories, not a shell flag
-- string.  Passing "-I..." here made every try_compile search a bogus path
-- like <scratch>/-I/prefix/include.
function M.dep_include_dirs(ctx, name)
    local m = ctx.dep(name)
    assert(m, "missing dependency: " .. tostring(name))
    return table.concat(util.uniq(m.includes or {}), ";")
end

function M.pkgconfig_dirs(ctx)
    local dirs = {}
    for _, p in ipairs(M.all_prefixes(ctx)) do
        for _, rel in ipairs({ "lib/pkgconfig", "lib64/pkgconfig", "share/pkgconfig" }) do
            local d = util.join(p, rel)
            if fs.isdir(d) then dirs[#dirs + 1] = d end
        end
    end
    for _, m in ipairs(ctx.all_dependencies or {}) do
        for _, d in ipairs(m.libdirs or {}) do
            local p = util.join(d, "pkgconfig")
            if fs.isdir(p) then dirs[#dirs + 1] = p end
        end
    end
    return util.uniq(dirs)
end

function M.restrict_pkgconfig(ctx)
    local dirs = table.concat(M.pkgconfig_dirs(ctx), ":")
    ctx.env.PKG_CONFIG_LIBDIR = dirs
    ctx.env.PKG_CONFIG_PATH = dirs

    -- Direct dependency include prefixes are the ONLY -I paths allowed from
    -- pkg-config cflags. --libs --static still sees the full dependency graph.
    local allowed = {}
    for _, m in ipairs(ctx.dependencies or {}) do
        for _, p in ipairs(m.includes or {}) do allowed[#allowed + 1] = p end
    end
    ctx.env.GCPKG_PKG_CONFIG_INCLUDE_PREFIXES =
        table.concat(util.uniq(allowed), ":")

    local real = "/usr/bin/pkg-config"
    assert(fs.isfile(real), "system pkg-config tool is missing: " .. real)
    local wrapper = util.join(ctx.store.bin, "gcpkg-pkg-config")
    fs.write(wrapper, [==[
#!/usr/bin/env bash
# gcpkg pkg-config wrapper: --static is needed for --libs, but must not drag
# private dependency include paths into --cflags for every compile unit.
set -u
real=${GCPKG_PKG_CONFIG_REAL:-/usr/bin/pkg-config}
[ -x "$real" ] || { echo "gcpkg: real pkg-config not executable: $real" >&2; exit 127; }

mode=libs
for arg in "$@"; do
    case "$arg" in
        --cflags|--cflags-only-I|--cflags-only-other) mode=cflags ;;
    esac
done

if [ "$mode" != cflags ]; then
    exec "$real" "$@"
fi

args=()
for arg in "$@"; do
    [ "$arg" = "--static" ] || args+=("$arg")
done
out=$("$real" "${args[@]}")
rc=$?
[ "$rc" -eq 0 ] || exit "$rc"

allowed=${GCPKG_PKG_CONFIG_INCLUDE_PREFIXES:-}
if [ -z "$allowed" ]; then
    printf '%s\n' "$out"
    exit 0
fi

IFS=: read -r -a prefixes <<< "$allowed"
kept=()
for token in $out; do
    if [[ "$token" == -I* ]]; then
        path=${token#-I}
        ok=0
        for prefix in "${prefixes[@]}"; do
            [ -n "$prefix" ] || continue
            if [[ "$path" == "$prefix"* ]]; then ok=1; break; fi
        done
        [ "$ok" -eq 1 ] && kept+=("$token")
    else
        kept+=("$token")
    fi
done
printf '%s\n' "${kept[*]}"
]==])
    ctx.exec({ "chmod", "+x", wrapper }, { quiet = true, check = false })
    ctx.env.GCPKG_PKG_CONFIG_REAL = real
    ctx.env.PKG_CONFIG = wrapper
    return dirs
end

function M.libdecor_source_only_plugins(ctx)
    -- Restrict pkg-config to the source-built dependency prefixes. The
    -- upstream Cairo/Pango plugin is only built when those source ports are
    -- present; otherwise only the source-built dummy plugin is installed.
    M.restrict_pkgconfig(ctx)
    local plugins = util.join(ctx.src, "src", "plugins", "meson.build")
    local dummy = util.join(ctx.src, "src", "plugins", "dummy", "meson.build")
    assert(fs.isfile(plugins) and fs.isfile(dummy),
           "libdecor Meson plugin files are missing")
    fs.write(plugins, [=[
gtk_dep = dependency('gtk+-3.0', required: get_option('gtk'))

plugin_include_path = include_directories('.')

cairo_dep = dependency('cairo', required: false, method: 'pkg-config')
pangocairo_dep = dependency('pangocairo', required: false, method: 'pkg-config')

if cairo_dep.found() and pangocairo_dep.found()
  subdir('common')
  subdir('cairo')
endif

subdir('dummy')

if gtk_dep.found()
  subdir('gtk')
endif
]=])
    fs.write(dummy, [=[
shared_module('decor-dummy',
  sources: [
    'libdecor-dummy.c',
  ],
  include_directories: [
    top_includepath,
    libdecor_includepath,
  ],
  gnu_symbol_visibility: 'hidden',
  dependencies: [
    libdecor_dep,
  ],
  install: true,
  install_dir: join_paths(plugindir),
)
]=])
end

function M.enable_source_wrap_proxy(ctx)
    local p = "http://127.0.0.1:7890"
    for _, k in ipairs({ "http_proxy", "https_proxy", "HTTP_PROXY", "HTTPS_PROXY",
                         "ALL_PROXY", "all_proxy" }) do
        ctx.env[k] = p
    end
    ctx.env.GIT_TERMINAL_PROMPT = "0"
end

local function direct_values(ctx, field)
    local out = {}
    for _, m in ipairs(ctx.dependencies or {}) do
        for _, value in ipairs(m[field] or {}) do
            out[#out + 1] = value
        end
    end
    return util.uniq(out)
end

-- Only direct dependency exports belong in --extra-cflags / --extra-ldflags.
-- ctx.includes / ctx.libdirs contain the whole transitive closure; injecting
-- those into a configure line made every compiler probe search dozens of
-- unrelated headers and was the R20 performance bug.
function M.flags(ctx)
    local cflags, ldflags = {}, {}
    for _, i in ipairs(direct_values(ctx, "includes")) do
        cflags[#cflags + 1] = "-I" .. i
    end
    for _, d in ipairs(direct_values(ctx, "defines")) do
        cflags[#cflags + 1] = "-D" .. d
    end
    for _, d in ipairs(direct_values(ctx, "libdirs")) do
        ldflags[#ldflags + 1] = "-L" .. d
    end
    return table.concat(cflags, " "), table.concat(ldflags, " ")
end

function M.license(ctx, files)
    local doc = util.join(ctx.prefix, "share", "doc", ctx.name)
    fs.mkdirs(doc)
    local copied = 0
    for _, f in ipairs(files) do
        local p = util.join(ctx.src, f)
        if fs.isfile(p) or fs.isdir(p) then
            ctx.exec({ "cp", "-a", p, doc }, { log = ctx.log })
            copied = copied + 1
        end
    end
    assert(copied > 0, "no license files installed for " .. ctx.name)
end

function M.clean_build(ctx)
    fs.rm(ctx.build_dir)
    fs.mkdirs(ctx.build_dir)
end

function M.sdl3_source_only_wayland(ctx)
    -- SDL's upstream check wants a host egl.pc. In a source-only stack the
    -- source-built wayland-egl.pc already provides the Wayland EGL window
    -- integration, and SDL_OPENGL/SDL_OPENGLES are off. Drop only that token.
    M.restrict_pkgconfig(ctx)
    local checks = util.join(ctx.src, "cmake", "sdlchecks.cmake")
    assert(fs.isfile(checks), "SDL3 sdlchecks.cmake is missing")
    local text = fs.read(checks)
    local old = 'set(WAYLAND_PKG_CONFIG_SPEC "wayland-client>=1.18" wayland-egl wayland-cursor egl "xkbcommon>=0.5.0")'
    local new = 'set(WAYLAND_PKG_CONFIG_SPEC "wayland-client>=1.18" wayland-egl wayland-cursor "xkbcommon>=0.5.0")'
    local start, finish = text:find(old, 1, true)
    if start then
        fs.write(checks, text:sub(1, start - 1) .. new .. text:sub(finish + 1))
    else
        assert(text:find(new, 1, true),
               "SDL3 Wayland pkg-config spec is neither upstream nor source-only")
    end
end

function M.patch_x265_cmake_policies(ctx)
    local cmake_lists = util.join(ctx.src, "source", "CMakeLists.txt")
    assert(fs.isfile(cmake_lists), "x265 source/CMakeLists.txt is missing")
    local text = fs.read(cmake_lists)
    local replacements = {
        { "cmake_policy(SET CMP0025 OLD)", "cmake_policy(SET CMP0025 NEW)" },
        { "cmake_policy(SET CMP0054 OLD)", "cmake_policy(SET CMP0054 NEW)" },
    }
    for _, r in ipairs(replacements) do
        local old, new = r[1], r[2]
        local start, finish = text:find(old, 1, true)
        if start then
            text = text:sub(1, start - 1) .. new .. text:sub(finish + 1)
        else
            assert(text:find(new, 1, true), "x265 policy is neither OLD nor NEW: " .. old)
        end
    end
    fs.write(cmake_lists, text)
end

return M
