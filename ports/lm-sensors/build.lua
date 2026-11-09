-- lm-sensors 3.6.0 -- gcpkg port definition.
-- hardware monitoring (libsensors); hand-written Makefile.


return {
    name = "lm-sensors",
    version = "3.6.0",
    license = "GPL-2.0/LGPL-2.1",
    homepage = "https://hwmon.wiki.kernel.org/lm_sensors",
    description = "Hardware monitoring (libsensors)",
    source = {
        url = "https://codeload.github.com/lm-sensors/lm-sensors/tar.gz/refs/tags/V3-6-0",
        sha256 = "0591f9fa0339f0d15e75326d0365871c2d4e2ed8aa1ff759b3a55d3734b7d197",
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
                   "cp -f sensors '" .. p .. "/sbin/' 2>/dev/null || true"
        ctx.exec({ "sh", "-c", cp }, { cwd = work, log = ctx.log })
        return {
            includes = { p .. "/include" },
            libdirs = { p .. "/lib" },
            libs = {
            "sensors",
          },
            binaries = { p .. "/sbin" },
        }
    end,
}
