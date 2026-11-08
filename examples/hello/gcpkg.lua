-- A project is managed by gcpkg too: build description + feature selection live
-- right here in the project directory. No separate "ports tree" checkout, no
-- manifest mode, no toolchain file.
local cc = require("gcpkg.build.cc")

return {
    name = "hello-gcpkg",
    version = "0.1.0",
    dependencies = { "openssl" },

    build = function(ctx)
        -- ctx.includes / libs / libdirs / link_flags are collected from ALL
        -- transitive dependencies' manifests; ctx.exec records commands in the
        -- merged compilation database.
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
            tag = "hello-gcpkg",
        }
        local binary = cc.link {
            objects = objects,
            output = ctx.build_dir .. "/hello-gcpkg",
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
