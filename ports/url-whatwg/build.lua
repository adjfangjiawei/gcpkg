-- url-whatwg 72bcabf -- gcpkg source port for ada's upa::url competitor.
-- All writes stay inside the store.  ICU comes from the source-built icu4c72
-- port through a local CONFIG package; test/example headers come from their
-- own source ports.  No configure-time downloads and no host discovery.
local recipe = require("gcpkg.recipe")
local fs = require("gcpkg.fs")
local util = require("gcpkg.util")
local cmake = require("gcpkg.build.cmake")

local function add_path(ctx, key, path)
    local prev = ctx.env[key]
    if not prev or prev == "" then
        ctx.env[key] = path
        return
    end
    for entry in prev:gmatch("[^:]+") do
        if entry == path then return end
    end
    ctx.env[key] = path .. ":" .. prev
end

local function dep_include(ctx, name)
    local m = assert(ctx.dep(name), "gcpkg: url-whatwg: missing dependency " .. name)
    local incs = m.includes or {}
    assert(#incs > 0, "gcpkg: url-whatwg: dependency " .. name .. " exports no include dir")
    return incs[1]
end

local function copy_header(ctx, src, dst)
    fs.mkdirs(util.dirname(dst))
    ctx.exec({ "cp", "-a", src, dst }, { cwd = ctx.src, log = ctx.log })
end

local function copy_wpt_data(ctx)
    local data = assert(ctx.dep("url-wpt-data"),
                        "gcpkg: url-whatwg: missing WPT data dependency")
    assert(data.prefix, "gcpkg: url-whatwg: url-wpt-data manifest has no prefix")
    local src = data.prefix .. "/share/url-wpt-data/wpt/."
    local dst = ctx.src .. "/test/wpt"
    fs.mkdirs(dst)
    ctx.exec({ "cp", "-a", src, dst },
             { cwd = ctx.src, log = ctx.log })
    for _, name in ipairs({
        "setters_tests.json", "toascii.json", "urltestdata.json",
        "percent-encoding.json", "IdnaTestV2.json",
    }) do
        assert(fs.isfile(dst .. "/" .. name),
               "gcpkg: url-whatwg: missing WPT data file " .. name)
    end
end

local function pre_build(ctx)
    local on = ctx.features.enabled
    if on["tests"] then
        copy_wpt_data(ctx)
        copy_header(ctx, dep_include(ctx, "doctest") .. "/doctest/doctest.h",
                    ctx.src .. "/deps/doctest/doctest.h")
        copy_header(ctx, dep_include(ctx, "picojson") .. "/picojson/picojson.h",
                    ctx.src .. "/deps/picojson/picojson.h")
        copy_header(ctx, dep_include(ctx, "ddt") .. "/ddt/DataDrivenTest.hpp",
                    ctx.src .. "/deps/ddt/DataDrivenTest.hpp")
    end
    if on["examples"] then
        copy_header(ctx, dep_include(ctx, "json-writer") .. "/json_writer/json_writer.h",
                    ctx.src .. "/deps/json_writer/json_writer.h")
    end
end

local function build(ctx)
    pre_build(ctx)
    local on = ctx.features.enabled
    local icu = assert(ctx.dep("icu4c72"),
                       "gcpkg: url-whatwg: icu4c72 dependency is required")
    assert(icu.prefix, "gcpkg: url-whatwg: icu4c72 manifest has no prefix")

    local prefixes, seen = {}, {}
    for _, m in ipairs(ctx.all_dependencies or {}) do
        if m.prefix and not seen[m.prefix] then
            seen[m.prefix] = true
            prefixes[#prefixes + 1] = m.prefix
        end
    end

    local defines = {
        CMAKE_CXX_STANDARD = on["cxx17"] and "17" or "11",
        CMAKE_INSTALL_LIBDIR = "lib",
        CMAKE_INSTALL_INCLUDEDIR = "include",
        CMAKE_EXPORT_COMPILE_COMMANDS = "ON",
        CMAKE_FIND_PACKAGE_PREFER_CONFIG = "TRUE",
        CMAKE_FIND_USE_SYSTEM_PACKAGE_REGISTRY = "FALSE",
        CMAKE_FIND_USE_PACKAGE_REGISTRY = "FALSE",
        ICU_ROOT = icu.prefix,
        ICU_DIR = icu.prefix .. "/lib/cmake/ICU",
    }
    if #prefixes > 0 then
        defines.CMAKE_PREFIX_PATH = table.concat(prefixes, ";")
    end

    add_path(ctx, "LD_LIBRARY_PATH", icu.prefix .. "/lib")
    add_path(ctx, "LD_LIBRARY_PATH", ctx.prefix .. "/lib")

    local result = cmake.all {
        src = ctx.src,
        build_dir = ctx.build_dir,
        prefix = ctx.prefix,
        exec = ctx.exec,
        log = ctx.log,
        jobs = ctx.jobs,
        env = ctx.env,
        defines = defines,
        args = ctx.feature_args(),
    }

    if on["tests"] then
        ctx.exec({ "ctest", "--output-on-failure" },
                 { cwd = ctx.build_dir, log = ctx.log, env = ctx.env })
    end

    return {
        includes = { ctx.prefix .. "/include" },
        libdirs = { ctx.prefix .. "/lib" },
        libs = { "upa_url" },
        binaries = {},
        defines = {}, link_flags = {},
        compdb_files = result.compdb_files,
    }
end

return recipe.define {
    name = "url-whatwg",
    version = "72bcabf",
    license = "BSD-2-Clause",
    homepage = "https://github.com/rmisev/url_whatwg",
    description = "WHATWG URL parser (upa::url) used by ada benchmarks",
    source = {
        url = "https://codeload.github.com/rmisev/url_whatwg/tar.gz/72bcabf9e138f1e90dc80507a991c2c68270145d",
        sha256 = "f4352ddbca70dfa4b8070b517529313dd9c707a03964befb6ddae1476a94de1c",
        strip = 1,
    },
    dependencies = {},
    build = build,
    exports = {
        includes = { "@PREFIX@/include" },
        libdirs = { "@LIBDIR@" },
        libs = { "upa_url" },
        binaries = {},
    },
}
