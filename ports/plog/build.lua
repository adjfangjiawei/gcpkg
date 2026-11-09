-- plog 1.1.10 -- gcpkg port definition.
-- Header-only C++ logging library.

local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "plog",
    version = "1.1.10",
    license = "MPL-2.0",
    homepage = "https://github.com/SergiusTheBest/plog",
    description = "Header-only C++ logging library",
    source = {
        url = "https://codeload.github.com/SergiusTheBest/plog/tar.gz/refs/tags/1.1.10",
        sha256 = "55a090fc2b46ab44d0dde562a91fe5fc15445a3caedfaedda89fe3925da4705a",
        strip = 1,
    },
    dependencies = {},
    cmake = {
        defines = {
          BUILD_TESTING = "OFF",
          CMAKE_BUILD_TYPE = "Release",
          CMAKE_INSTALL_LIBDIR = "lib",
          BUILD_SHARED_LIBS = "OFF",
          PLOG_BUILD_SAMPLES = "OFF",
          PLOG_BUILD_TESTS = "OFF",
          PLOG_INSTALL = "ON",
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
