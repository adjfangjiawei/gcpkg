-- libgudev 238 -- gcpkg port definition.
-- udev device enumeration on GLib; Meson build.

local recipe = require("gcpkg.recipe")

return recipe.meson {
    name = "libgudev",
    version = "238",
    license = "LGPL-2.1",
    homepage = "https://gitlab.gnome.org/GNOME/libgudev",
    description = "udev device enumeration for GLib",
    source = {
        url = "https://codeload.github.com/GNOME/libgudev/tar.gz/refs/tags/238",
        sha256 = "443c702c6339775f413f45d13309b2c641a94530bb27981142a2605eedb0aafd",
        strip = 1,
    },
    dependencies = {
        "glib",
      },
    meson = {
        options = {},
        args = {},
    },
    exports = {
      includes = {
        "@PREFIX@/include",
        "@PREFIX@/include/gudev-1.0",
      },
      libdirs = {
        "@LIBDIR@",
      },
      libs = {
        "gudev-1.0",
      },
      binaries = {},
    },
}
