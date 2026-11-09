-- IP Virtual Server administration utility (Linux IPVS)
-- gcpkg port definition.
local recipe = require("gcpkg.recipe")

return recipe.make {
    name = "ipvsadm",
    version = "1.31",
    description = "IP Virtual Server administration utility (Linux IPVS)",
    license = "GPL-2.0",
    homepage = "https://www.linuxvirtualserver.org",
    source = {
        url = "https://mirrors.edge.kernel.org/pub/linux/utils/kernel/ipvsadm/ipvsadm-1.31.tar.xz",
        sha256 = "1a0a5e25b5a1226435d2fb76341656f83a710183aebb0d204db39c0ec3bedfdb",
        strip = 1,
    },
    dependencies = { "libnl", "popt" },
    make = {
        vars = function(ctx) return {
              BUILD_ROOT = ctx.prefix,
              INCLUDE = '-I' .. table.concat(ctx.includes or {}, ' -I'),
              LIBS = "-lpopt -lnl-genl-3 -lnl-3"
            } end,
        targets = {},
        install_target = "install",
        jobs = 1,
    },
    exports = {
      includes = { "@PREFIX@/include" },
      libdirs = { "@LIBDIR@" },
      binaries = { "@PREFIX@/sbin" }
    },
}
