-- Linux capabilities library (POSIX.1e)
-- ONE library, ONE build.lua and ONE features.yaml. Upstream sources
-- are downloaded verbatim (sha256 verified) and never patched.
local recipe = require("gcpkg.recipe")

return recipe.make {
    name = "libcap",
    version = "2.76",
    description = "Linux capabilities library (POSIX.1e)",
    license = "BSD-3-Clause",
    homepage = "https://sites.google.com/site/fullycapable",
    source = {
        url = "https://mirrors.edge.kernel.org/pub/linux/libs/security/linux-privs/libcap2/libcap-2.76.tar.xz",
        sha256 = "629da4ab29900d0f7fcc36227073743119925fd711c99a1689bbf5c9b40c8e6f",
        strip = 1,
    },
    dependencies = {},
    make = {
        vars = function(ctx) return {
              prefix = ctx.prefix,
              lib = "lib",
              SHARED = "no",
              PAM_CAP = "no",
              GOLANG = "no"
            } end,
        install_target = "install",
    },
    exports = {
      includes = { "@PREFIX@/include" },
      libdirs = { "@LIBDIR@" },
      libs = { "cap", "psx" },
      binaries = { "@PREFIX@/sbin" }
    },
}
