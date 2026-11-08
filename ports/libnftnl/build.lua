-- Netfilter nf_tables netlink library
-- ONE library, ONE build.lua and ONE features.yaml. Upstream sources
-- are downloaded verbatim (sha256 verified) and never patched.
local recipe = require("gcpkg.recipe")

return recipe.autotools {
    name = "libnftnl",
    version = "1.2.8",
    description = "Netfilter nf_tables netlink library",
    license = "GPL-2.0",
    homepage = "https://www.netfilter.org/projects/libnftnl/",
    source = {
        url = "https://www.netfilter.org/projects/libnftnl/files/libnftnl-1.2.8.tar.xz",
        sha256 = "37fea5d6b5c9b08de7920d298de3cdc942e7ae64b1a3e8b880b2d390ae67ad95",
        strip = 1,
    },
    dependencies = { "libmnl" },
    autotools = {
        args = { "--disable-shared", "--disable-doxygen" },
    },
    exports = {
      includes = { "@PREFIX@/include/libnftnl", "@PREFIX@/include" },
      libdirs = { "@LIBDIR@" },
      libs = { "nftnl" }
    },
}
