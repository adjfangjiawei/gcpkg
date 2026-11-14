-- libselinux 3.8 -- gcpkg port definition.
-- SELinux userspace library; build in src/.


return {
    name = "libselinux",
    version = "3.8",
    license = "LGPL-2.1",
    homepage = "https://github.com/SELinuxProject/selinux",
    description = "SELinux userspace library",
    source = {
        url = "https://github.com/SELinuxProject/selinux/releases/download/3.8/libselinux-3.8.tar.gz",
        sha256 = "0c3756bca047c9270281d7c4dcdecd000b72e38a183c930661eba9690839b541",
        strip = 1,
    },
    dependencies = {
        "pcre2",
        "libseccomp",
      },
    build = function(ctx)
        local util = require("gcpkg.util")
        local j = tostring(ctx.jobs or 4)
        local work = util.join(ctx.src, "src")
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
                   "cp -f true '" .. p .. "/sbin/' 2>/dev/null || true"
        ctx.exec({ "sh", "-c", cp }, { cwd = work, log = ctx.log })
        return {
            includes = { p .. "/include" },
            libdirs = { p .. "/lib" },
            libs = {
            "selinux",
          },
            binaries = { p .. "/sbin" },
        }
    end,
}
