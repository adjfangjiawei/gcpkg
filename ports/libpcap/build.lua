-- Packet capture library
-- gcpkg port definition.
local recipe = require("gcpkg.recipe")

return recipe.autotools {
    name = "libpcap",
    version = "1.10.5",
    description = "Packet capture library",
    license = "BSD-3-Clause",
    homepage = "https://www.tcpdump.org",
    source = {
        url = "https://www.tcpdump.org/release/libpcap-1.10.5.tar.xz",
        sha256 = "84fa89ac6d303028c1c5b754abff77224f45eca0a94eb1a34ff0aa9ceece3925",
        strip = 1,
    },
    dependencies = {},
    autotools = {
        args = { "--disable-shared", "--without-libnl", "--disable-dbus", "--disable-bluetooth", "--disable-rdma", "--disable-usb", "--disable-netmap", "--disable-dag", "--disable-septel", "--disable-snf", "--disable-tc" },
    },
    exports = {
      includes = { "@PREFIX@/include" },
      libdirs = { "@LIBDIR@" },
      libs = { "pcap" }
    },
}
