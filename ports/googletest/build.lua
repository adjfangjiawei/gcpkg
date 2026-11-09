-- googletest 1.15.2 -- gcpkg port definition.
-- C++ test framework; installed headers and static libs.

local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "googletest",
    version = "1.15.2",
    license = "BSD-3-Clause",
    homepage = "https://github.com/google/googletest",
    description = "C++ testing and mocking framework",
    source = {
        url = "https://codeload.github.com/google/googletest/tar.gz/refs/tags/v1.15.2",
        sha256 = "7b42b4d6ed48810c5362c265a17faebe90dc2373c885e5216439d37927f02926",
        strip = 1,
    },
    dependencies = {},
    cmake = {
        defines = {
          BUILD_GMOCK = "ON",
          INSTALL_GTEST = "ON",
          gtest_force_shared_crt = "ON",
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
        "gtest",
        "gmock",
        "gtest_main",
        "gmock_main",
      },
      binaries = {},
    },
}
