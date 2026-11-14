-- mvfst 2026.10.26.00 -- gcpkg port definition.
-- QUIC transport layer for proxygen.


local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "mvfst",
    version = "2026.10.26.00",
    description = "Facebook QUIC implementation",
    license = "MIT",
    homepage = "https://github.com/facebook/mvfst",
    source = {
        url = "https://codeload.github.com/facebook/mvfst/tar.gz/refs/tags/v2026.10.26.00",
        sha256 = "7b2f2a84a5df3689d29a2c3c482b508e1d26251d568e9faf0ced22fb113e6dcd",
        strip = 1,
    },
    dependencies = {
        "folly",
        "fizz",
        "cmake",
      },
    cmake = {
        defines = {
          BUILD_TESTING = "OFF",
          BUILD_TESTS = "OFF",
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
        "mvfst",
      },
      binaries = {},
    },
}
