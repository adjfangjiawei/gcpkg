-- Netlink protocol library suite
-- ONE library, ONE build.lua and ONE features.yaml. Upstream sources
-- are downloaded verbatim (sha256 verified) and never patched.
local recipe = require("gcpkg.recipe")

return recipe.autotools {
    name = "libnl",
    version = "3.11.0",
    description = "Netlink protocol library suite",
    license = "LGPL-2.1",
    homepage = "https://github.com/thom311/libnl",
    source = {
        url = "https://github.com/thom311/libnl/releases/download/libnl3_11_0/libnl-3.11.0.tar.gz",
        sha256 = "2a56e1edefa3e68a7c00879496736fdbf62fc94ed3232c0baba127ecfa76874d",
        strip = 1,
    },
    dependencies = {},
    autotools = {
        args = { "--disable-cli", "--disable-shared" },
    },
    exports = {
      includes = { "@PREFIX@/include/libnl3", "@PREFIX@/include" },
      libdirs = { "@LIBDIR@" },
      libs = { "nl-3", "nl-genl-3", "nl-route-3" }
    },
}
