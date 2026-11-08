-- systemd: libsystemd/libudev and the system/service manager
-- ONE library, ONE build.lua and ONE features.yaml. Upstream sources
-- are downloaded verbatim (sha256 verified) and never patched.
local recipe = require("gcpkg.recipe")

return recipe.meson {
    name = "systemd",
    version = "257.7",
    description = "systemd: libsystemd/libudev and the system/service manager",
    license = "LGPL-2.1/GPL-2.0",
    homepage = "https://systemd.io",
    source = {
        url = "https://github.com/systemd/systemd/archive/refs/tags/v257.7.tar.gz",
        sha256 = "70ecf759260549486045d065555d2f8a0ac0b8523d8f58227559fbd6d7523b08",
        strip = 1,
    },
    dependencies = {},
    meson = {
        options = function(ctx) return {
              mode = "developer",
              tests = "false",
              man = "disabled",
              hwdb = "false",
              translations = "false",
              ["static-libsystemd"] = "false",
              ["static-libudev"] = "false",
              ["link-udev-shared"] = "false",
              ["split-usr"] = "false",
              ["split-bin"] = "false",
              rootprefix = ctx.prefix,
              rootlibdir = ctx.prefix .. '/lib',
              ["sysvinit-path"] = ctx.prefix .. '/etc/init.d',
              ["sysvrcnd-path"] = ctx.prefix .. '/etc/rc.d',
              ["rc-local"] = ctx.prefix .. '/etc/rc.local'
            } end,
        auto_features = "disabled",
    },
    exports = {
      includes = { "@PREFIX@/include" },
      libdirs = { "@LIBDIR@" },
      libs = { "systemd", "udev" },
      binaries = { "@PREFIX@/bin" }
    },
}
