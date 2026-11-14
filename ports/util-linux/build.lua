-- libuuid / libblkid / libmount / libsmartcols / libfdisk
-- gcpkg port definition.
local recipe = require("gcpkg.recipe")

return recipe.meson {
    name = "util-linux",
    version = "2.41",
    description = "libuuid / libblkid / libmount / libsmartcols / libfdisk",
    license = "LGPL-2.1/BSD/GPL",
    homepage = "https://github.com/util-linux/util-linux",
    source = {
        url = "https://mirrors.edge.kernel.org/pub/linux/utils/util-linux/v2.41/util-linux-2.41.tar.xz",
        sha256 = "81ee93b3cfdfeb7d7c4090cedeba1d7bbce9141fd0b501b686b3fe475ddca4c6",
        strip = 1,
    },
    dependencies = {},
    meson = {
        options = {
          ["build-libuuid"] = "enabled",
          ["build-libblkid"] = "enabled",
          ["build-libmount"] = "enabled",
          ["build-libsmartcols"] = "enabled",
          ["build-libfdisk"] = "enabled",
          ["build-python"] = "disabled",
          nls = "disabled",
          ncursesw = "disabled",
          readline = "disabled",
          selinux = "disabled",
          audit = "disabled",
          systemd = "disabled",
          cryptsetup = "disabled",
          magic = "disabled",
          econf = "disabled",
          zlib = "disabled",
          ["libpcre2-posix"] = "disabled"
        },
        auto_features = "disabled",
    },
    exports = {
      includes = { "@PREFIX@/include" },
      libdirs = { "@LIBDIR@" },
      libs = { "uuid", "blkid", "mount", "smartcols", "fdisk" }
    },
}
