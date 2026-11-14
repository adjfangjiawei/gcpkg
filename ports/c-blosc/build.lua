-- c-blosc 1.21.6 -- gcpkg port definition.
-- Blosc blocking compressor; uses bundled codecs to stay self-contained.

local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "c-blosc",
    version = "1.21.6",
    license = "BSD-3-Clause",
    homepage = "https://github.com/Blosc/c-blosc",
    description = "Blocking, shuffling and lossless compression",
    source = {
        url = "https://codeload.github.com/Blosc/c-blosc/tar.gz/refs/tags/v1.21.6",
        sha256 = "9fcd60301aae28f97f1301b735f966cc19e7c49b6b4321b839b4579a0c156f38",
        strip = 1,
    },
    dependencies = {},
    cmake = {
        defines = {
          BUILD_TESTS = "OFF",
          BUILD_BENCHMARKS = "OFF",
          BUILD_SHARED = "OFF",
          BUILD_STATIC = "ON",
          PREFER_EXTERNAL_LZ4 = "OFF",
          PREFER_EXTERNAL_ZLIB = "OFF",
          PREFER_EXTERNAL_ZSTD = "OFF",
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
        "blosc",
      },
      binaries = {},
    },
}
