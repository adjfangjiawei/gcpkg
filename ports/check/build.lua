-- check 0.15.2 -- gcpkg port definition.
-- C unit-test framework; static libcheck only.

local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "check",
    version = "0.15.2",
    license = "LGPL-2.1",
    homepage = "https://libcheck.github.io/check",
    description = "Unit testing framework for C",
    source = {
        url = "https://codeload.github.com/libcheck/check/tar.gz/refs/tags/0.15.2",
        sha256 = "998d355294bb94072f40584272cf4424571c396c631620ce463f6ea97aa67d2e",
        strip = 1,
    },
    dependencies = {},
    cmake = {
        defines = {
          BUILD_TESTING = "OFF",
          CHECK_ENABLE_TESTS = "OFF",
          ENABLE_SUBUNIT = "OFF",
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
        "check",
      },
      binaries = {},
    },
}
