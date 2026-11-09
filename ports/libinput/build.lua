-- Input device handling library for Wayland compositors
-- gcpkg port definition.
local recipe = require("gcpkg.recipe")

return recipe.meson {
    name = "libinput",
    version = "1.28.1",
    description = "Input device handling library for Wayland compositors",
    license = "MIT",
    homepage = "https://gitlab.freedesktop.org/libinput/libinput",
    source = {
        url = "https://gitlab.freedesktop.org/libinput/libinput/-/archive/1.28.1/libinput-1.28.1.tar.gz",
        sha256 = "a13f8c9a7d93df3c85c66afd135f0296701d8d32f911991b7aa4273fdd6a42a3",
        strip = 1,
    },
    dependencies = { "libevdev", "wayland", "wayland-protocols" },
    meson = {
        options = {
          tests = "false",
          documentation = "false",
          ["debug-gui"] = "false",
          libwacom = "false",
          ["install-tests"] = "false"
        },
        auto_features = "disabled",
    },
    exports = {
      includes = { "@PREFIX@/include" },
      libdirs = { "@LIBDIR@" },
      libs = { "input" }
    },
}
