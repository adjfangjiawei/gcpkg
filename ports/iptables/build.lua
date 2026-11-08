-- iptables / nftables userspace packet filtering tools and libxtables
-- ONE library, ONE build.lua and ONE features.yaml. Upstream sources
-- are downloaded verbatim (sha256 verified) and never patched.
local recipe = require("gcpkg.recipe")

return recipe.autotools {
    name = "iptables",
    version = "1.8.11",
    description = "iptables / nftables userspace packet filtering tools and libxtables",
    license = "GPL-2.0",
    homepage = "https://www.netfilter.org/projects/iptables/",
    source = {
        url = "https://www.netfilter.org/projects/iptables/files/iptables-1.8.11.tar.xz",
        sha256 = "d87303d55ef8c92bcad4dd3f978b26d272013642b029425775f5bad1009fe7b2",
        strip = 1,
    },
    dependencies = { "libmnl", "libnftnl" },
    autotools = {
        args = { "--disable-shared", "--disable-devel", "--disable-libipq", "--disable-bpf-compiler", "--disable-nfsynproxy", "--disable-connlabel" },
    },
    exports = {
      includes = { "@PREFIX@/include" },
      libdirs = { "@LIBDIR@" },
      libs = { "xtables", "ip4tc", "ip6tc", "iptc" },
      binaries = { "@PREFIX@/sbin" }
    },
}
