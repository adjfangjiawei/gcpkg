-- gflags 2.2.2 -- gcpkg port definition.
-- C++ command-line flags; bottom of the gflags -> glog chain.

local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "gflags",
    version = "2.2.2",
    license = "BSD-3-Clause",
    homepage = "https://github.com/gflags/gflags",
    description = "C++ command-line flag parsing",
    source = {
        url = "https://codeload.github.com/gflags/gflags/tar.gz/refs/tags/v2.2.2",
        sha256 = "34af2f15cf7367513b352bdcd2493ab14ce43692d2dcd9dfc499492966c64dcf",
        strip = 1,
    },
    dependencies = {},
    cmake = {
        defines = {
          BUILD_TESTING = "OFF",
          BUILD_NESTED_TESTS = "OFF",
          BUILD_SHARED_LIBS = "OFF",
          BUILD_STATIC_LIBS = "ON",
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
        "gflags",
      },
      binaries = {},
    },
}
