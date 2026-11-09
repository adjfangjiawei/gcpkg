-- mongoose 7.15 -- ONE port, ONE build.lua + ONE features.yaml.
-- Single-file embedded networking library; compiled via gcpkg's CC interceptor.
-- Static checks in tests/r12.sh; GCPKG_R12_DYNAMIC=1 builds it for real.
-- Upstream is never patched: all adaptation lives in this file.
local util = require("gcpkg.util")
local fs = require("gcpkg.fs")

return {
    name = "mongoose",
    version = "7.15",
    license = "GPL-2.0-only OR commercial",
    homepage = "https://mongoose.ws",
    description = "Single-file embedded networking library",
    source = {
        url = "https://codeload.github.com/cesanta/mongoose/tar.gz/refs/tags/7.15",
        sha256 = "efcb5aa89b85d40373dcff3241316ddc0f2f130ad7f05c9c964f8cc1e2078a0b",
        strip = 1,
    },
    dependencies = {},
    build = function(ctx)
        local incdir = util.join(ctx.prefix, "include")
        local libdir = util.join(ctx.prefix, "lib")
        fs.mkdirs(incdir)
        fs.mkdirs(libdir)
        local function compile(src, args, cxx)
            local obj = util.join(ctx.build_dir, util.basename(src):gsub("%.", "_") .. ".o")
            local cmd = { cxx and ctx.compiler.wrapper_cxx or ctx.compiler.wrapper_cc,
                          "-c", "-O2" }
            for _, a in ipairs(args) do cmd[#cmd + 1] = a end
            cmd[#cmd + 1] = util.join(ctx.src, src)
            cmd[#cmd + 1] = "-o"
            cmd[#cmd + 1] = obj
            ctx.record({ directory = ctx.src, file = util.join(ctx.src, src),
                         arguments = cmd, output = obj, tag = ctx.key })
            ctx.exec(cmd, { cwd = ctx.src, log = ctx.log })
            return obj
        end
        local obj = compile("mongoose.c", { "-DMG_TLS=MG_TLS_NONE", "-I", ctx.src }, false)
        ctx.exec({ "ar", "rcs", util.join(libdir, "libmongoose.a"), obj },
                 { cwd = ctx.src, log = ctx.log })
        ctx.exec({ "cp", "-a", util.join(ctx.src, "mongoose.h"), incdir }, { log = ctx.log })
        return {
            includes = { incdir }, libdirs = { libdir },
            libs = { "mongoose" }, binaries = {},
        }
    end,
}
