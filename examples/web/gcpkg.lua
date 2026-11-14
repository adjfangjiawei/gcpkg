-- A project that sits on TOP of the whole dependency DAG:
--   web -> curl -> {nghttp2, libssh2, cares, ...} -> {openssl, zlib, ...}
-- gcpkg builds everything bottom-up and merges every layer's compile commands.
local cc = require("gcpkg.build.cc")

return {
    name = "web-smoke",
    version = "0.1.0",
    dependencies = { "curl" },

    build = function(ctx)
        local objects = cc.compile {
            sources = { "src/main.c" },
            includes = ctx.includes,
            defines = ctx.defines,
            flags = { "-std=c11", "-O2", "-g", "-Wall" },
            outdir = ctx.build_dir .. "/obj",
            cwd = ctx.project_dir,
            compiler = ctx.compiler.cc,
            exec = ctx.exec,
            record = ctx.record,
            log = ctx.log,
            tag = "web-smoke",
        }
        local binary = cc.link {
            objects = objects,
            output = ctx.build_dir .. "/web-smoke",
            libdirs = ctx.libdirs,
            libs = ctx.libs,
            flags = ctx.link_flags,
            cwd = ctx.project_dir,
            compiler = ctx.compiler.cc,
            exec = ctx.exec,
            log = ctx.log,
        }
        gcpkg.log.step("built " .. binary)
        return {}
    end,
}
