-- Generic PCI access library (X.org)
-- gcpkg port definition.
local recipe = require("gcpkg.recipe")

return recipe.meson {
    name = "libpciaccess",
    version = "0.18.1",
    description = "Generic PCI access library (X.org)",
    license = "MIT",
    homepage = "https://gitlab.freedesktop.org/xorg/lib/libpciaccess",
    source = {
        url = "https://www.x.org/archive/individual/lib/libpciaccess-0.18.1.tar.xz",
        sha256 = "4af43444b38adb5545d0ed1c2ce46d9608cc47b31c2387fc5181656765a6fa76",
        strip = 1,
    },
    dependencies = { "zlib" },
    meson = {
        options = {
          zlib = "enabled"
        },
        auto_features = "disabled",
    },
    exports = {
      includes = { "@PREFIX@/include" },
      libdirs = { "@LIBDIR@" },
      libs = { "pciaccess" }
    },
}
