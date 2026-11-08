-- lzfse 1.0 -- ONE library, ONE build.lua + ONE features.yaml.
-- Verification: static registry/graph tests here; real builds for a
-- subset live in tests/extra.sh (GCPKG_EXTRA_DYNAMIC=1).
-- Apple LZFSE codec; small standalone CMake project.
-- Upstream is never patched: all adaptation is in this file.

local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "lzfse",
    version = "1.0",
    license = "BSD-3-Clause",
    homepage = "https://github.com/lzfse/lzfse",
    description = "Apple LZFSE compression library",
    source = {
        url = "https://codeload.github.com/lzfse/lzfse/tar.gz/refs/tags/lzfse-1.0",
        sha256 = "cf85f373f09e9177c0b21dbfbb427efaedc02d035d2aade65eb58a3cbf9ad267",
        strip = 1,
    },
    dependencies = {},
    cmake = {
        defines = {
          BUILD_TESTING = "OFF",
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
        "lzfse",
      },
      binaries = {},
    },
}
