-- fizz 2026.10.26.00 -- gcpkg port definition.
-- Facebook v2026.10.26.00 release line, same tag as folly/wangle/mvfst/proxygen.


local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "fizz",
    version = "2026.10.26.00",
    description = "Facebook TLS 1.3 library",
    license = "BSD-3-Clause",
    homepage = "https://github.com/facebookincubator/fizz",
    source = {
        url = "https://codeload.github.com/facebookincubator/fizz/tar.gz/refs/tags/v2026.10.26.00",
        sha256 = "3f481c7157e91ff3dbede77290db539355f297db73f74593c81bf7c602229ebe",
        strip = 1,
    },
    dependencies = {
        "folly",
        "openssl",
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
        "fizz",
      },
      binaries = {},
    },
}
