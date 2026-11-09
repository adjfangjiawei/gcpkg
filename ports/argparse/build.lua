-- argparse 3.2 -- gcpkg port definition.
-- Header-only C++ argument parser.

local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "argparse",
    version = "3.2",
    license = "MIT",
    homepage = "https://github.com/p-ranav/argparse",
    description = "Header-only C++ command-line argument parser",
    source = {
        url = "https://codeload.github.com/p-ranav/argparse/tar.gz/refs/tags/v3.2",
        sha256 = "9dcb3d8ce0a41b2a48ac8baa54b51a9f1b6a2c52dd374e28cc713bab0568ec98",
        strip = 1,
    },
    dependencies = {},
    cmake = {
        defines = {
          BUILD_TESTING = "OFF",
          CMAKE_BUILD_TYPE = "Release",
          CMAKE_INSTALL_LIBDIR = "lib",
          BUILD_SHARED_LIBS = "OFF",
          ARGPARSE_BUILD_TESTS = "OFF",
          ARGPARSE_BUILD_SAMPLES = "OFF",
          ARGPARSE_INSTALL = "ON",
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
      libs = {},
      binaries = {},
    },
}
