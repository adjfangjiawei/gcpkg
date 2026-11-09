-- libpng 1.6.59 -- gcpkg port definition.
-- PNG library on the existing zlib port; headers also under include/libpng16.

local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "libpng",
    version = "1.6.59",
    license = "libpng-2.0",
    homepage = "https://www.libpng.org/pub/png/libpng.html",
    description = "PNG image format library",
    source = {
        url = "https://codeload.github.com/pnggroup/libpng/tar.gz/refs/tags/v1.6.59",
        sha256 = "2540302a1844ad2b2b501977abecfa850f265f97b78f065a712ab4074a89f5b5",
        strip = 1,
    },
    dependencies = {
        "zlib",
      },
    cmake = {
        defines = {
          PNG_TESTS = "OFF",
          PNG_TOOLS = "OFF",
        },
        args = {},
    },
    exports = {
      includes = {
        "@PREFIX@/include",
        "@PREFIX@/include/libpng16",
      },
      libdirs = {
        "@LIBDIR@",
      },
      libs = {
        "png16",
      },
      binaries = {},
    },
}
