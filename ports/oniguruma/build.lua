-- oniguruma 6.9.10 -- ONE library, ONE build.lua + ONE features.yaml.
-- Verification: static registry/graph tests here; real builds for a
-- subset live in tests/linux-base.sh (GCPKG_BASE_DYNAMIC=1).
-- Regex engine; CMake build.
-- Upstream is never patched: all adaptation is in this file.

local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "oniguruma",
    version = "6.9.10",
    license = "BSD-2-Clause",
    homepage = "https://github.com/kkos/oniguruma",
    description = "Regular expression library",
    source = {
        url = "https://codeload.github.com/kkos/oniguruma/tar.gz/refs/tags/v6.9.10",
        sha256 = "ad92309d0d13eebc27f6592e875f3efbfa3dda2bf6da5952e00f0a2120c921a8",
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
        "onig",
      },
      binaries = {},
    },
}
