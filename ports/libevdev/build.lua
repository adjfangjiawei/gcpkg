-- Linux evdev input event wrapper library
-- gcpkg port definition.
local recipe = require("gcpkg.recipe")

return recipe.meson {
    name = "libevdev",
    version = "1.13.4",
    description = "Linux evdev input event wrapper library",
    license = "MIT",
    homepage = "https://www.freedesktop.org/wiki/Software/libevdev/",
    source = {
        url = "https://www.freedesktop.org/software/libevdev/libevdev-1.13.4.tar.xz",
        sha256 = "f00ab8d42ad8b905296fab67e13b871f1a424839331516642100f82ad88127cd",
        strip = 1,
    },
    dependencies = {},
    meson = {
        options = {
          tests = "disabled",
          tools = "disabled",
          documentation = "disabled"
        },
        auto_features = "disabled",
    },
    exports = {
      includes = { "@PREFIX@/include/libevdev-1.0", "@PREFIX@/include" },
      libdirs = { "@LIBDIR@" },
      libs = { "evdev" }
    },
}
