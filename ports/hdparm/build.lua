-- hdparm 9.65 -- gcpkg port definition.
-- ATA/SATA disk parameter query; hand-written Makefile.


return {
    name = "hdparm",
    version = "9.65",
    license = "BSD-2-Clause",
    homepage = "https://sourceforge.net/projects/hdparm/",
    description = "ATA/SATA disk parameter query tool",
    source = {
        url = "https://downloads.sourceforge.net/project/hdparm/hdparm/hdparm-9.65.tar.gz",
        sha256 = "d14929f910d060932e717e9382425d47c2e7144235a53713d55a94f7de535a4b",
        strip = 1,
    },
    dependencies = {},
    build = function(ctx)
        local util = require("gcpkg.util")
        local j = tostring(ctx.jobs or 4)
        local work = ctx.src
        local p = ctx.prefix
        -- Many kernel-tool Makefiles hardcode CC=gcc; a command-line override
        -- keeps the gcpkg-intercept wrapper in place so compdb is produced.
        ctx.exec({ "make", "-j" .. j, "CC=" .. ctx.env.CC }, { cwd = work, log = ctx.log })
        -- Hand-written kernel-tool Makefiles install into /sbin or /usr, which
        -- a non-root build cannot do. Collect the built archives, headers and
        -- binaries into the gcpkg prefix instead (upstream is not patched).
        local cp = "mkdir -p '" .. p .. "/lib' '" .. p .. "/include' '" .. p .. "/sbin' && " ..
                   "cp -f *.a '" .. p .. "/lib/' 2>/dev/null || true; " ..
                   "cp -f lib/*.a '" .. p .. "/lib/' 2>/dev/null || true; " ..
                   "cp -f *.h '" .. p .. "/include/' 2>/dev/null || true; " ..
                   "cp -f lib/*.h '" .. p .. "/include/' 2>/dev/null || true; " ..
                   "cp -f include/*.h '" .. p .. "/include/' 2>/dev/null || true; " ..
                   "cp -f hdparm '" .. p .. "/sbin/' 2>/dev/null || true"
        ctx.exec({ "sh", "-c", cp }, { cwd = work, log = ctx.log })
        return {
            includes = { p .. "/include" },
            libdirs = { p .. "/lib" },
            libs = {},
            binaries = { p .. "/sbin" },
        }
    end,
}
