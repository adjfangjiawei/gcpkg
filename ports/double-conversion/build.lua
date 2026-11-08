-- double-conversion 3.3.0 -- ONE library, ONE build.lua + ONE features.yaml.
-- Verification: static registry/graph tests in tests/r10.sh; real
-- builds in GCPKG_R10_DYNAMIC=1 ./tests/r10.sh.
-- IEEE-754 decimal conversion routines; static build.
-- Upstream is never patched: all adaptation is in this file.

local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "double-conversion",
    version = "3.3.0",
    license = "BSD-3-Clause",
    homepage = "https://github.com/google/double-conversion",
    description = "Binary-decimal and decimal-binary IEEE-754 conversion",
    source = {
        url = "https://codeload.github.com/google/double-conversion/tar.gz/refs/tags/v3.3.0",
        sha256 = "04ec44461850abbf33824da84978043b22554896b552c5fd11a9c5ae4b4d296e",
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
        "double-conversion",
      },
      binaries = {},
    },
}
