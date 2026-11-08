-- X11 protocol headers and pkg-config files (headers-only port)
-- ONE library, ONE build.lua and ONE features.yaml. Upstream sources
-- are downloaded verbatim (sha256 verified) and never patched.
local recipe = require("gcpkg.recipe")

return recipe.meson {
    name = "xorgproto",
    version = "2024.1",
    description = "X11 protocol headers and pkg-config files (headers-only port)",
    license = "MIT",
    homepage = "https://gitlab.freedesktop.org/xorg/proto/xorgproto",
    source = {
        url = "https://www.x.org/archive/individual/proto/xorgproto-2024.1.tar.xz",
        sha256 = "372225fd40815b8423547f5d890c5debc72e88b91088fbfb13158c20495ccb59",
        strip = 1,
    },
    dependencies = {},
    meson = {
        options = {
          legacy = "true"
        },
        auto_features = "disabled",
    },
    exports = {
      includes = { "@PREFIX@/include" }
    },
}
