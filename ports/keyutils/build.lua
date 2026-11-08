-- keyutils 1.6.3 -- ONE library, ONE build.lua + ONE features.yaml.
-- Verification: static registry/graph tests here; real builds for a
-- subset live in tests/linux-kernel.sh (GCPKG_KERNEL_DYNAMIC=1).
-- Linux kernel keyring; hand-written Makefile.
-- Upstream is never patched: all adaptation is in this file.


return {
    name = "keyutils",
    version = "1.6.3",
    license = "GPL-2.0/LGPL-2.1",
    homepage = "https://git.kernel.org/pub/scm/linux/kernel/git/dhowells/keyutils.git",
    description = "Linux kernel keyring library and tools",
    source = {
        url = "https://git.kernel.org/pub/scm/linux/kernel/git/dhowells/keyutils.git/snapshot/keyutils-1.6.3.tar.gz",
        sha256 = "a61d5706136ae4c05bd48f86186bcfdbd88dd8bd5107e3e195c924cfc1b39bb4",
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
                   "cp -f keyctl request-key '" .. p .. "/sbin/' 2>/dev/null || true"
        ctx.exec({ "sh", "-c", cp }, { cwd = work, log = ctx.log })
        return {
            includes = { p .. "/include" },
            libdirs = { p .. "/lib" },
            libs = {
            "keyutils",
          },
            binaries = { p .. "/sbin" },
        }
    end,
}
