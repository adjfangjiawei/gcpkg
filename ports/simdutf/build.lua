-- simdutf 5.6.3 -- gcpkg port definition.
-- SIMD Unicode validation/transcoding.

local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "simdutf",
    version = "5.6.3",
    license = "MIT",
    homepage = "https://github.com/simdutf/simdutf",
    description = "SIMD Unicode validation and transcoding",
    source = {
        url = "https://codeload.github.com/simdutf/simdutf/tar.gz/refs/tags/v5.6.3",
        sha256 = "503070ddf27e26c051b9500dfc7354ec8850e11076f47db32635931c85b630c0",
        strip = 1,
    },
    dependencies = {},
    cmake = {
        defines = {
          BUILD_TESTING = "OFF",
          SIMDUTF_TESTS = "OFF",
          SIMDUTF_BENCHMARKS = "OFF",
          SIMDUTF_TOOLS = "OFF",
          SIMDUTF_FUZZERS = "OFF",
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
        "simdutf",
      },
      binaries = {},
    },
}
