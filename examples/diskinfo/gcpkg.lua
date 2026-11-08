-- A project sitting on top of the disk-information stack:
--   diskinfo -> {libnvme (-> liburing), libatasmart, pciutils (-> zlib)}
-- gcpkg builds/resolves every layer bottom-up and merges ALL of their
-- compile commands into one project-level compile_commands.json, so clangd
-- can jump from this file into nvme/tree.h, atasmart.h, pci.h and back.
--
-- This smoke project compiles only (no link): a real disk query needs
-- device permissions, and the three static libraries pull in kernel-specific
-- transitive dependencies. The point here is the merged compilation database.
local cc = require("gcpkg.build.cc")

return {
    name = "diskinfo-smoke",
    version = "0.1.0",
    dependencies = { "libnvme", "libatasmart", "pciutils" },

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
            tag = "diskinfo-smoke",
        }
        gcpkg.log.step("compiled " .. #objects .. " project objects; merged compdb written")
        return {}
    end,
}
