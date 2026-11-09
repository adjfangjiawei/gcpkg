-- cereal 1.3.2 -- gcpkg port definition.
-- Header-only C++ serialization; just upstream install rules.

local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "cereal",
    version = "1.3.2",
    license = "BSD-3-Clause",
    homepage = "https://github.com/USCiLab/cereal",
    description = "Header-only C++ serialization library",
    source = {
        url = "https://codeload.github.com/USCiLab/cereal/tar.gz/refs/tags/v1.3.2",
        sha256 = "16a7ad9b31ba5880dac55d62b5d6f243c3ebc8d46a3514149e56b5e7ea81f85f",
        strip = 1,
    },
    dependencies = {},
    cmake = {
        defines = {
          BUILD_TESTING = "OFF",
          CMAKE_BUILD_TYPE = "Release",
          CMAKE_INSTALL_LIBDIR = "lib",
          BUILD_SHARED_LIBS = "OFF",
          JUST_INSTALL_CEREAL = "ON",
          CEREAL_INSTALL = "ON",
          BUILD_TESTS = "OFF",
          BUILD_DOC = "OFF",
          BUILD_SANDBOX = "OFF",
          SKIP_PERFORMANCE_COMPARISON = "ON",
          WITH_WERROR = "OFF",
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
