-- libebur128 1.2.6 -- gcpkg port definition.
-- EBU R128 loudness library; static build.

local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "libebur128",
    version = "1.2.6",
    license = "MIT",
    homepage = "https://github.com/jiixyj/libebur128",
    description = "EBU R128 loudness measurement library",
    source = {
        url = "https://codeload.github.com/jiixyj/libebur128/tar.gz/refs/tags/v1.2.6",
        sha256 = "baa7fc293a3d4651e244d8022ad03ab797ca3c2ad8442c43199afe8059faa613",
        strip = 1,
    },
    dependencies = {},
    cmake = {
        defines = {
          BUILD_TESTING = "OFF",
          CMAKE_BUILD_TYPE = "Release",
          CMAKE_INSTALL_LIBDIR = "lib",
          BUILD_SHARED_LIBS = "OFF",
          ENABLE_TESTS = "OFF",
          ENABLE_FUZZER = "OFF",
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
        "ebur128",
      },
      binaries = {},
    },
}
