-- snappy 1.2.2 -- gcpkg port definition.
-- Google's fast compressor; static CMake build.

local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "snappy",
    version = "1.2.2",
    license = "BSD-3-Clause",
    homepage = "https://github.com/google/snappy",
    description = "Fast compression/decompression",
    source = {
        url = "https://codeload.github.com/google/snappy/tar.gz/refs/tags/1.2.2",
        sha256 = "90f74bc1fbf78a6c56b3c4a082a05103b3a56bb17bca1a27e052ea11723292dc",
        strip = 1,
    },
    dependencies = {},
    cmake = {
        defines = {
          SNAPPY_BUILD_TESTS = "OFF",
          SNAPPY_BUILD_BENCHMARKS = "OFF",
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
        "snappy",
      },
      binaries = {},
    },
}
