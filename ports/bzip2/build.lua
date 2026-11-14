-- bzip2 1.0.8 -- Layer L0, hand-written Makefile (no CMake, no autotools).
-- Kept as a CUSTOM build.lua on purpose: it shows that the recipe layer is
-- optional and that any upstream build system can be driven directly.
local util = require("gcpkg.util")
local fs = require("gcpkg.fs")
local make = require("gcpkg.build.make")

return {
    name = "bzip2",
    version = "1.0.8",
    description = "bzip2 / libbz2 lossless compression library",
    license = "bzip2-1.0.6",
    homepage = "https://sourceware.org/bzip2/",
    source = {
        url = "https://sourceware.org/pub/bzip2/bzip2-1.0.8.tar.gz",
        sha256 = "ab5a03176ee106d3f0fa90e381da478ddae405918153cca248e682cd0c4a2269",
        strip = 1,
    },
    dependencies = {},

    build = function(ctx)
        -- bzip2's Makefile hard-codes CC=gcc; command-line variables override it
        -- so the gcpkg interceptor still sees every compile invocation.
        local vars = {
            CC = ctx.compiler.wrapper_cc,
            CFLAGS = "-fPIC -O2 -g",
            PREFIX = ctx.prefix,
        }
        local targets = { "libbz2.a", "bzip2", "bzip2recover" }
        if not ctx.features.enabled["no-tests"] then
            targets[#targets + 1] = "test"
        end
        make.run {
            cwd = ctx.src, exec = ctx.exec, log = ctx.log, jobs = ctx.jobs,
            vars = vars, targets = targets,
        }
        make.run {
            cwd = ctx.src, exec = ctx.exec, log = ctx.log, jobs = ctx.jobs,
            vars = vars, targets = { "install" },
        }

        if ctx.features.enabled.shared then
            ctx.exec({ "make", "-f", "Makefile-libbz2_so",
                       "CC=" .. ctx.compiler.wrapper_cc, "CFLAGS=-fPIC -O2 -g" })
            local lib = util.join(ctx.prefix, "lib")
            fs.mkdirs(lib)
            ctx.exec({ "cp", "libbz2.so.1.0.8", lib .. "/" })
            ctx.exec({ "ln", "-sf", "libbz2.so.1.0.8", util.join(lib, "libbz2.so.1.0") })
            ctx.exec({ "ln", "-sf", "libbz2.so.1.0", util.join(lib, "libbz2.so") })
        end

        return {
            includes = { util.join(ctx.prefix, "include") },
            libdirs = { util.join(ctx.prefix, "lib") },
            libs = { "bz2" },
            binaries = { util.join(ctx.prefix, "bin") },
        }
    end,
}
