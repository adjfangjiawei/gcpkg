-- Keyboard handling library (Wayland/X11 keymaps)
-- gcpkg port definition.
local recipe = require("gcpkg.recipe")

return recipe.meson {
    name = "libxkbcommon",
    version = "1.7.0",
    description = "Keyboard handling library (Wayland/X11 keymaps)",
    license = "MIT",
    homepage = "https://xkbcommon.org",
    source = {
        url = "https://xkbcommon.org/download/libxkbcommon-1.7.0.tar.xz",
        sha256 = "65782f0a10a4b455af9c6baab7040e2f537520caa2ec2092805cdfd36863b247",
        strip = 1,
    },
    dependencies = {},
    meson = {
        options = {
          ["enable-x11"] = "false",
          ["enable-wayland"] = "false",
          ["enable-docs"] = "false",
          ["enable-tools"] = "false",
          ["enable-xkbregistry"] = "false"
        },
        auto_features = "disabled",
    },
    exports = {
      includes = { "@PREFIX@/include" },
      libdirs = { "@LIBDIR@" },
      libs = { "xkbcommon" }
    },
}
