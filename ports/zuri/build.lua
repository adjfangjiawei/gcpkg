-- zuri b2fddbf -- gcpkg source port for ada's Zig/C-ABI URI competitor.
-- The pinned tarball is built with the source/tool port `zig` only; all
-- artifacts and caches stay inside the store.  No host Zig, no configure-time
-- fetch, no library-side platform probe.
local recipe = require("gcpkg.recipe")
local fs = require("gcpkg.fs")
local util = require("gcpkg.util")
local cc = require("gcpkg.build.cc")

local function zig_env(ctx)
    local m = assert(ctx.dep("zig"),
                     "gcpkg: zuri: missing zig tool dependency")
    local prefix = assert(m.prefix,
                          "gcpkg: zuri: zig manifest has no prefix")
    local old = ctx.env.PATH or ""
    ctx.env.PATH = prefix .. "/bin:" .. prefix .. ":" .. old
    ctx.env.ZIG_GLOBAL_CACHE_DIR = ctx.build_dir .. "/zig-global-cache"
    fs.mkdirs(ctx.env.ZIG_GLOBAL_CACHE_DIR)
    return prefix
end

local function build(ctx)
    local on = ctx.features.enabled
    local zigPrefix = zig_env(ctx)
    local incdir = ctx.prefix .. "/include"
    local libdir = ctx.prefix .. "/lib"
    local cmakedir = libdir .. "/cmake/zuri"
    local bindir = ctx.prefix .. "/bin"
    local docdir = ctx.prefix .. "/share/doc/zuri"
    local objdir = ctx.build_dir .. "/obj"
    fs.mkdirs(incdir)
    fs.mkdirs(libdir)
    fs.mkdirs(bindir)
    fs.mkdirs(cmakedir)
    fs.mkdirs(docdir)
    fs.mkdirs(objdir)

    if on["library"] then
        ctx.exec({ "zig", "build", "-j1" },
                 { cwd = ctx.src, log = ctx.log, env = ctx.env })
        local native = ctx.src .. "/zig-out/lib/libzuri.a"
        assert(fs.isfile(native),
               "gcpkg: zuri: zig build did not produce libzuri.a")
        ctx.exec({ "cp", "-a", ctx.src .. "/zig-out/lib/.", libdir .. "/" },
                 { cwd = ctx.src, log = ctx.log })
        if fs.isdir(ctx.src .. "/zig-out/bin") then
            ctx.exec({ "cp", "-a", ctx.src .. "/zig-out/bin/.", bindir .. "/" },
                     { cwd = ctx.src, log = ctx.log })
        end
    end

    if on["tests"] then
        ctx.exec({ "zig", "build", "-j1", "test" },
                 { cwd = ctx.src, log = ctx.log, env = ctx.env })
    end

    if on["headers"] then
        ctx.exec({ "cp", "-a", ctx.src .. "/zuri.h", incdir .. "/zuri.h" },
                 { cwd = ctx.src, log = ctx.log })
    end
    if on["cmake-package"] then
        -- Upstream's Makefile links demo.c with -no-pie: the Zig 0.11 static
        -- archive has absolute .rodata relocations and cannot be linked into a
        -- host PIE.  Propagate that requirement to CMake consumers as well.
        local cfg = cmakedir .. "/zuri-config.cmake"
        ctx.exec({ "cp", "-a", ctx.src .. "/package/zuri-config.cmake", cfg },
                 { cwd = ctx.src, log = ctx.log })
        local content = assert(fs.read(cfg),
                               "gcpkg: zuri: cannot read zuri-config.cmake")
        fs.write(cfg, content ..
            "\nif(TARGET zuri)\n" ..
            "    set_property(TARGET zuri APPEND PROPERTY INTERFACE_LINK_OPTIONS \"-no-pie\")\n" ..
            "endif()\n")
    end
    if on["license"] then
        ctx.exec({ "cp", "-a", ctx.src .. "/LICENSE", docdir .. "/LICENSE" },
                 { cwd = ctx.src, log = ctx.log })
    end

    if on["examples"] or on["sanity"] then
        assert(on["library"],
               "gcpkg: zuri: demo needs the Zig library artifacts")
        assert(on["headers"],
               "gcpkg: zuri: demo needs the C ABI header")
        local demo = cc.executable {
            sources = { ctx.src .. "/demo.c" },
            includes = { incdir, ctx.src },
            flags = { "-std=c11" },
            cwd = ctx.build_dir, outdir = objdir,
            compiler = ctx.compiler.wrapper_cc,
            exec = ctx.exec, record = ctx.record, log = ctx.log,
            tag = "zuri", cxx = false,
            output = bindir .. "/zuri_demo",
            flags = { "-std=c11", "-no-pie" },
            libdirs = { libdir }, libs = { "zuri" },
        }
        if on["sanity"] then
            ctx.exec({ demo },
                     { cwd = ctx.build_dir, log = ctx.log, env = ctx.env })
        end
    end

    return {
        includes = { incdir },
        libdirs = { libdir },
        libs = { "zuri" },
        binaries = { bindir },
        defines = {},
        link_flags = {},
        compdb_files = {},
    }
end

return recipe.define {
    name = "zuri",
    version = "b2fddbf",
    license = "CC0-1.0",
    homepage = "https://github.com/pascaldekloe/zuri",
    description = "ZURI strict URI library (Zig/C ABI) used by ada benchmarks",
    source = {
        url = "https://codeload.github.com/pascaldekloe/zuri/tar.gz/b2fddbfc4c5d5036233c3610e74ecb872d2f0477",
        sha256 = "f51453a295a502c8d1b7b064f3a00611aaa4e3c4f2d9d4f832a4a019a3e10217",
        strip = 1,
    },
    dependencies = {},
    build = build,
    exports = {
        includes = { "@PREFIX@/include" },
        libdirs = { "@LIBDIR@" },
        libs = { "zuri" },
        binaries = { "@PREFIX@/bin" },
    },
}
