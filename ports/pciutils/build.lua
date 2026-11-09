-- pciutils 3.15.0 -- gcpkg port definition.
-- PCI enumeration (lspci) + libpci; hand-written Makefile, install target writes /sbin so build.lua collects artifacts into the prefix.


return {
    name = "pciutils",
    version = "3.15.0",
    license = "GPL-2.0",
    homepage = "https://mj.ucw.cz/sw/pciutils/",
    description = "PCI device enumeration (lspci) and libpci",
    source = {
        url = "https://codeload.github.com/pciutils/pciutils/tar.gz/refs/tags/v3.15.0",
        sha256 = "06f467642057599acf396bc17340452fac3308f1e08be19e0c32587e42d7017b",
        strip = 1,
    },
    dependencies = {
        "zlib",
      },
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
                   "cp -f lspci setpci update-pciids '" .. p .. "/sbin/' 2>/dev/null || true"
        ctx.exec({ "sh", "-c", cp }, { cwd = work, log = ctx.log })
        return {
            includes = { p .. "/include" },
            libdirs = { p .. "/lib" },
            libs = {
            "pci",
          },
            binaries = { p .. "/sbin" },
        }
    end,
}
