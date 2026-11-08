-- Wayland protocol XML specifications (data-only port)
-- ONE library, ONE build.lua and ONE features.yaml. Upstream sources
-- are downloaded verbatim (sha256 verified) and never patched.
local recipe = require("gcpkg.recipe")

return recipe.meson {
    name = "wayland-protocols",
    version = "1.45",
    description = "Wayland protocol XML specifications (data-only port)",
    license = "MIT",
    homepage = "https://gitlab.freedesktop.org/wayland/wayland-protocols",
    source = {
        url = "https://gitlab.freedesktop.org/wayland/wayland-protocols/-/archive/1.45/wayland-protocols-1.45.tar.gz",
        sha256 = "460dad72a6c84b2a7d80745bee43d96ba117f4e3dfc4d7c45f83f66469ea27df",
        strip = 1,
    },
    dependencies = { "wayland" },
    meson = {
        options = {
          tests = "false"
        },
        auto_features = "disabled",
    },
    exports = {
      includes = { "@PREFIX@/include" }
    },
}
