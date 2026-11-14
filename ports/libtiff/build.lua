-- libtiff 4.7.0 -- gcpkg port definition.
-- TIFF on zlib + xz + zstd + libjpeg-turbo (existing and new ports).

local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "libtiff",
    version = "4.7.0",
    license = "libtiff",
    homepage = "https://libtiff.gitlab.io/libtiff/",
    description = "TIFF image format library",
    source = {
        url = "https://download.osgeo.org/libtiff/tiff-4.7.0.tar.gz",
        sha256 = "67160e3457365ab96c5b3286a0903aa6e78bdc44c4bc737d2e486bcecb6ba976",
        strip = 1,
    },
    dependencies = {
        "zlib",
        "xz",
        "zstd",
        "libjpeg-turbo",
      },
    cmake = {
        defines = {
          BUILD_TESTING = "OFF",
          tests = "OFF",
          tools = "OFF",
        },
        args = {},
    },
    exports = {
      includes = {
        "@PREFIX@/include",
      },
      libdirs = {
        "@LIBDIR@",
      },
      libs = {
        "tiff",
      },
      binaries = {},
    },
}
