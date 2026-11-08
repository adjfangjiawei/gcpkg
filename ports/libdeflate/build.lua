-- libdeflate 1.26 -- ONE library, ONE build.lua + ONE features.yaml.
-- Verification: static registry/graph tests here; real builds for a
-- subset live in tests/linux-base.sh (GCPKG_BASE_DYNAMIC=1).
-- libdeflate 1.26 ships CMakeLists.txt only (no top-level Makefile).
-- Upstream is never patched: all adaptation is in this file.

local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "libdeflate",
    version = "1.26",
    license = "MIT",
    homepage = "https://github.com/ebiggers/libdeflate",
    description = "Fast DEFLATE/zlib/gzip compression",
    source = {
        url = "https://codeload.github.com/ebiggers/libdeflate/tar.gz/refs/tags/v1.26",
        sha256 = "bba03fffc5538576213675ce6968fcff6ce2e67d82e4d5febea2d05f9f13cf85",
        strip = 1,
    },
    dependencies = {},
    cmake = {
        defines = {
          LIBDEFLATE_BUILD_TESTS = "OFF",
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
        "deflate",
      },
      binaries = {},
    },
}
