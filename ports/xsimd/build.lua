-- xsimd 13.0.0 -- gcpkg port definition.
-- Header-only C++ SIMD wrappers.

local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "xsimd",
    version = "13.0.0",
    license = "BSD-3-Clause",
    homepage = "https://github.com/xtensor-stack/xsimd",
    description = "Header-only C++ SIMD wrappers",
    source = {
        url = "https://codeload.github.com/xtensor-stack/xsimd/tar.gz/refs/tags/13.0.0",
        sha256 = "8bdbbad0c3e7afa38d88d0d484d70a1671a1d8aefff03f4223ab2eb6a41110a3",
        strip = 1,
    },
    dependencies = {},
    cmake = {
        defines = {
          BUILD_TESTING = "OFF",
          XSIMD_BUILD_TESTS = "OFF",
          XSIMD_INSTALL = "ON",
          XSIMD_REFACTORING = "OFF",
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
