-- Minimalistic netlink library (netfilter)
-- ONE library, ONE build.lua and ONE features.yaml. Upstream sources
-- are downloaded verbatim (sha256 verified) and never patched.
local recipe = require("gcpkg.recipe")

return recipe.autotools {
    name = "libmnl",
    version = "1.0.5",
    description = "Minimalistic netlink library (netfilter)",
    license = "LGPL-2.1",
    homepage = "https://www.netfilter.org/projects/libmnl/",
    source = {
        url = "https://www.netfilter.org/projects/libmnl/files/libmnl-1.0.5.tar.bz2",
        sha256 = "274b9b919ef3152bfb3da3a13c950dd60d6e2bcd54230ffeca298d03b40d0525",
        strip = 1,
    },
    dependencies = {},
    autotools = {
        args = { "--disable-doxygen", "--disable-shared" },
    },
    exports = {
      includes = { "@PREFIX@/include" },
      libdirs = { "@LIBDIR@" },
      libs = { "mnl" }
    },
}
