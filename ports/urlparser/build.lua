-- urlparser 69c09ed -- gcpkg port (netmindms/urlparser).
-- The upstream tarball has no build system: one header, one implementation
-- translation unit and a self-contained example.  All default features are
-- built from the source tarball with gcpkg's compiler wrappers.
local recipe = require("gcpkg.recipe")
local fs = require("gcpkg.fs")
local util = require("gcpkg.util")
local cc = require("gcpkg.build.cc")

local function copy(ctx, src, dst)
    fs.mkdirs(util.dirname(dst))
    ctx.exec({ "cp", "-a", src, dst }, { cwd = ctx.src, log = ctx.log })
end

return recipe.define {
    name = "urlparser",
    version = "69c09ed",
    license = "MIT",
    homepage = "https://github.com/netmindms/urlparser",
    description = "Small C++ URL parser used as an ada benchmark competitor",
    source = {
        url = "https://codeload.github.com/netmindms/urlparser/tar.gz/69c09ed6ab022223e749f54e9158f0eedfcc8d28",
        sha256 = "1d2735a9247730429be5e84dff6453987f6da9a84b98436e0cd3560c6780fbe5",
        strip = 1,
    },
    dependencies = {},
    build = function(ctx)
        local on = ctx.features.enabled
        local incdir = ctx.prefix .. "/include"
        local libdir = ctx.prefix .. "/lib"
        local bindir = ctx.prefix .. "/bin"
        local srcdir = ctx.prefix .. "/share/urlparser/src"
        local docdir = ctx.prefix .. "/share/doc/urlparser"
        fs.mkdirs(incdir); fs.mkdirs(libdir); fs.mkdirs(bindir)
        fs.mkdirs(ctx.build_dir)
        local cxx = ctx.compiler.wrapper_cxx

        local objs = cc.compile {
            sources = { ctx.src .. "/src/EdUrlParser.cpp" },
            includes = { ctx.src .. "/src" },
            flags = { "-std=c++17", "-O3", "-fPIC" },
            cwd = ctx.src, outdir = ctx.build_dir .. "/obj_lib",
            compiler = cxx, exec = ctx.exec, record = ctx.record,
            log = ctx.log, tag = "urlparser",
        }
        if on["static"] then
            local arcmd = { "ar", "rcs", libdir .. "/liburlparser.a" }
            for _, o in ipairs(objs) do arcmd[#arcmd + 1] = o end
            ctx.exec(arcmd, { cwd = ctx.build_dir, log = ctx.log })
        end
        if on["shared"] then
            cc.link { objects = objs, output = libdir .. "/liburlparser.so",
                      compiler = cxx, flags = { "-shared" },
                      cwd = ctx.build_dir, exec = ctx.exec, log = ctx.log }
        end

        if on["example"] then
            local exobjs = cc.compile {
                sources = { ctx.src .. "/src/exam.cpp" },
                includes = { ctx.src .. "/src" },
                flags = { "-std=c++17", "-O2" },
                cwd = ctx.src, outdir = ctx.build_dir .. "/obj_exam",
                compiler = cxx, exec = ctx.exec, record = ctx.record,
                log = ctx.log, tag = "urlparser",
            }
            local all = {}
            for _, o in ipairs(objs) do all[#all + 1] = o end
            for _, o in ipairs(exobjs) do all[#all + 1] = o end
            local exe = bindir .. "/urlparser-example"
            cc.link { objects = all, output = exe, compiler = cxx,
                      flags = {}, cwd = ctx.build_dir, exec = ctx.exec,
                      log = ctx.log }
            ctx.exec({ exe }, { cwd = ctx.build_dir, log = ctx.log })
        end

        copy(ctx, ctx.src .. "/src/EdUrlParser.h", incdir .. "/EdUrlParser.h")
        if on["sources"] then
            for _, f in ipairs({ "EdUrlParser.cpp", "EdUrlParser.h", "exam.cpp" }) do
                copy(ctx, ctx.src .. "/src/" .. f, srcdir .. "/" .. f)
            end
        end
        if on["license"] then
            for _, f in ipairs({ "LICENSE.md", "README.md" }) do
                copy(ctx, ctx.src .. "/" .. f, docdir .. "/" .. f)
            end
        end
        return {
            includes = { incdir }, libdirs = { libdir },
            libs = { "urlparser" }, binaries = { bindir },
            defines = {}, link_flags = {}, compdb_files = {},
        }
    end,
    exports = {
        includes = { "@PREFIX@/include" },
        libdirs = { "@LIBDIR@" },
        libs = { "urlparser" },
        binaries = { "@PREFIX@/bin" },
    },
}
