-- tinyxml2 10.0.0 -- ONE library, ONE build.lua + ONE features.yaml.
-- Verification: static registry/graph tests in tests/r10.sh; real
-- builds in GCPKG_R10_DYNAMIC=1 ./tests/r10.sh.
-- Small C++ XML parser; tests off.
-- Upstream is never patched: all adaptation is in this file.

local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "tinyxml2",
    version = "10.0.0",
    license = "Zlib",
    homepage = "https://github.com/leethomason/tinyxml2",
    description = "Simple, small, efficient C++ XML parser",
    source = {
        url = "https://codeload.github.com/leethomason/tinyxml2/tar.gz/refs/tags/10.0.0",
        sha256 = "3bdf15128ba16686e69bce256cc468e76c7b94ff2c7f391cc5ec09e40bff3839",
        strip = 1,
    },
    dependencies = {},
    cmake = {
        defines = {
          BUILD_TESTING = "OFF",
          tinyxml2_BUILD_TESTING = "OFF",
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
        "tinyxml2",
      },
      binaries = {},
    },
}
