-- httpparser 2.9.4 -- gcpkg port (nodejs/http-parser).
-- Upstream is a single C file plus a hand-written Makefile.  Build every
-- default feature directly from the source tarball: static/shared library,
-- the upstream test binaries (compiled AND executed), the contrib tools and
-- an exported source directory.  No configure-time downloads, no probes.
local recipe = require("gcpkg.recipe")
local fs = require("gcpkg.fs")
local util = require("gcpkg.util")
local cc = require("gcpkg.build.cc")

local function copy(ctx, src, dst)
    fs.mkdirs(util.dirname(dst))
    ctx.exec({ "cp", "-a", src, dst }, { cwd = ctx.src, log = ctx.log })
end

return recipe.define {
    name = "httpparser",
    version = "2.9.4",
    license = "MIT",
    homepage = "https://github.com/nodejs/http-parser",
    description = "HTTP request/response parser in C",
    source = {
        url = "https://codeload.github.com/nodejs/http-parser/tar.gz/refs/tags/v2.9.4",
        sha256 = "467b9e30fd0979ee301065e70f637d525c28193449e1b13fbcb1b1fab3ad224f",
        strip = 1,
    },
    dependencies = {},
    build = function(ctx)
        local on = ctx.features.enabled
        local incdir = ctx.prefix .. "/include"
        local libdir = ctx.prefix .. "/lib"
        local bindir = ctx.prefix .. "/bin"
        local srcdir = ctx.prefix .. "/share/httpparser/src"
        local docdir = ctx.prefix .. "/share/doc/httpparser"
        fs.mkdirs(incdir); fs.mkdirs(libdir); fs.mkdirs(bindir)
        fs.mkdirs(ctx.build_dir)

        local function compile(sources, outdir, defines, compiler, flags)
            return cc.compile {
                sources = sources, includes = { ctx.src }, defines = defines or {},
                flags = flags or { "-O3", "-fPIC" },
                cwd = ctx.src, outdir = ctx.build_dir .. "/" .. outdir,
                compiler = compiler or ctx.compiler.wrapper_cc,
                exec = ctx.exec, record = ctx.record, log = ctx.log,
                tag = "httpparser",
            }
        end
        local function link(objects, output, compiler, flags)
            return cc.link {
                objects = objects, output = output,
                compiler = compiler or ctx.compiler.wrapper_cc,
                flags = flags or {},
                cwd = ctx.build_dir, exec = ctx.exec, log = ctx.log,
            }
        end

        local libObjs = compile({ ctx.src .. "/http_parser.c" }, "obj_lib",
                                { "HTTP_PARSER_STRICT=0" })
        if on["static"] then
            local arcmd = { "ar", "rcs", libdir .. "/libhttp_parser.a" }
            for _, o in ipairs(libObjs) do arcmd[#arcmd + 1] = o end
            ctx.exec(arcmd, { cwd = ctx.build_dir, log = ctx.log })
        end
        if on["shared"] then
            link(libObjs, libdir .. "/libhttp_parser.so.2.9.4",
                 nil, { "-shared", "-Wl,-soname,libhttp_parser.so.2.9.4" })
        end

        if on["tests"] then
            for _, mode in ipairs({ { "test_g", "1", "-O0", "-g" },
                                    { "test_fast", "0", "-O3" } }) do
                local name, strict = mode[1], mode[2]
                local flags = { mode[3] }
                if mode[4] then flags[#flags + 1] = mode[4] end
                local objs = compile({ ctx.src .. "/http_parser.c",
                                       ctx.src .. "/test.c" },
                                     "obj_" .. name, { "HTTP_PARSER_STRICT=" .. strict },
                                     nil, flags)
                local exe = ctx.build_dir .. "/" .. name
                link(objs, exe, nil, {})
                ctx.exec({ exe }, { cwd = ctx.build_dir, log = ctx.log })
            end
        end

        if on["tools"] then
            for _, tool in ipairs({ "url_parser", "parsertrace" }) do
                local objs = compile({ ctx.src .. "/contrib/" .. tool .. ".c" },
                                     "obj_" .. tool, { "HTTP_PARSER_STRICT=0" })
                local all = {}
                for _, o in ipairs(libObjs) do all[#all + 1] = o end
                for _, o in ipairs(objs) do all[#all + 1] = o end
                link(all, bindir .. "/httpparser-" .. tool, nil, {})
            end
        end

        copy(ctx, ctx.src .. "/http_parser.h", incdir .. "/http_parser.h")
        if on["sources"] then
            copy(ctx, ctx.src .. "/http_parser.c", srcdir .. "/http_parser.c")
            copy(ctx, ctx.src .. "/http_parser.h", srcdir .. "/http_parser.h")
        end
        if on["license"] then
            for _, f in ipairs({ "LICENSE-MIT", "AUTHORS", "README.md" }) do
                copy(ctx, ctx.src .. "/" .. f, docdir .. "/" .. f)
            end
        end
        return {
            includes = { incdir }, libdirs = { libdir },
            libs = { "http_parser" }, binaries = { bindir },
            defines = {}, link_flags = {}, compdb_files = {},
        }
    end,
    exports = {
        includes = { "@PREFIX@/include" },
        libdirs = { "@LIBDIR@" },
        libs = { "http_parser" },
        binaries = { "@PREFIX@/bin" },
    },
}
