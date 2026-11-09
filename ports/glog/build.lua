-- glog 0.7.1 -- gcpkg port definition.
-- Google logging library on the external gflags port.

local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "glog",
    version = "0.7.1",
    license = "BSD-3-Clause",
    homepage = "https://github.com/google/glog",
    description = "Google logging library built on gflags",
    source = {
        url = "https://codeload.github.com/google/glog/tar.gz/refs/tags/v0.7.1",
        sha256 = "00e4a87e87b7e7612f519a41e491f16623b12423620006f59f5688bfd8d13b08",
        strip = 1,
    },
    dependencies = {
        "gflags",
      },
    cmake = {
        defines = {
          BUILD_TESTING = "OFF",
          WITH_GFLAGS = "ON",
          WITH_UNWIND = "OFF",
          WITH_GTEST = "OFF",
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
        "glog",
      },
      binaries = {},
    },
}
