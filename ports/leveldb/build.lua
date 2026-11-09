-- leveldb 1.23 -- gcpkg port definition.
-- LevelDB key-value store; tests and benchmarks off.

local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "leveldb",
    version = "1.23",
    license = "BSD-3-Clause",
    homepage = "https://github.com/google/leveldb",
    description = "Fast key-value storage library",
    source = {
        url = "https://codeload.github.com/google/leveldb/tar.gz/refs/tags/1.23",
        sha256 = "9a37f8a6174f09bd622bc723b55881dc541cd50747cbd08831c2a82d620f6d76",
        strip = 1,
    },
    dependencies = {},
    cmake = {
        defines = {
          BUILD_TESTING = "OFF",
          CMAKE_BUILD_TYPE = "Release",
          CMAKE_INSTALL_LIBDIR = "lib",
          BUILD_SHARED_LIBS = "OFF",
          LEVELDB_BUILD_TESTS = "OFF",
          LEVELDB_BUILD_BENCHMARKS = "OFF",
          LEVELDB_INSTALL = "ON",
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
        "leveldb",
      },
      binaries = {},
    },
}
