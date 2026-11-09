-- X11 authorisation library
-- gcpkg port definition.
local recipe = require("gcpkg.recipe")

return recipe.autotools {
    name = "libXau",
    version = "1.0.12",
    description = "X11 authorisation library",
    license = "MIT",
    homepage = "https://gitlab.freedesktop.org/xorg/lib/libXau",
    source = {
        url = "https://www.x.org/archive/individual/lib/libXau-1.0.12.tar.xz",
        sha256 = "74d0e4dfa3d39ad8939e99bda37f5967aba528211076828464d2777d477fc0fb",
        strip = 1,
    },
    dependencies = { "xorgproto" },
    autotools = {
        args = { "--disable-shared" },
    },
    exports = {
      includes = { "@PREFIX@/include" },
      libdirs = { "@LIBDIR@" },
      libs = { "Xau" }
    },
}
