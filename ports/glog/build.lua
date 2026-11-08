-- glog 0.7.1 -- ONE library, ONE build.lua + ONE features.yaml.
-- Verification: static registry/graph tests in tests/r10.sh; real
-- builds in GCPKG_R10_DYNAMIC=1 ./tests/r10.sh.
-- Google logging library on the external gflags port.
-- Upstream is never patched: all adaptation is in this file.

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
