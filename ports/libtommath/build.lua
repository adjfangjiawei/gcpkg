-- libtommath 1.3.0 -- gcpkg port definition.
-- Multiple-precision integers; CMake output name tommath.

local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "libtommath",
    version = "1.3.0",
    license = "Unlicense",
    homepage = "https://github.com/libtom/libtommath",
    description = "Multiple-precision integer arithmetic",
    source = {
        url = "https://codeload.github.com/libtom/libtommath/tar.gz/refs/tags/v1.3.0",
        sha256 = "6d099e93ff00fa9b18346f4bcd97dcc48c3e91286f7e16c4ac5515a7171c3149",
        strip = 1,
    },
    dependencies = {},
    cmake = {
        defines = {
          BUILD_TESTING = "OFF",
          BUILD_SHARED_LIBS = "OFF",
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
        "tommath",
      },
      binaries = {},
    },
}
