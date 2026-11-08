-- abseil 20240722.0 -- ONE library, ONE build.lua + ONE features.yaml.
-- Verification: static registry/graph tests in tests/r10.sh; real
-- builds in GCPKG_R10_DYNAMIC=1 ./tests/r10.sh.
-- Abseil C++ foundation: CMake package config installed for re2.
-- Upstream is never patched: all adaptation is in this file.

local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "abseil",
    version = "20240722.0",
    license = "Apache-2.0",
    homepage = "https://abseil.io",
    description = "Abseil C++ common libraries (foundation for re2)",
    source = {
        url = "https://codeload.github.com/abseil/abseil-cpp/tar.gz/refs/tags/20240722.0",
        sha256 = "f50e5ac311a81382da7fa75b97310e4b9006474f9560ac46f54a9967f07d4ae3",
        strip = 1,
    },
    dependencies = {},
    cmake = {
        defines = {
          BUILD_TESTING = "OFF",
          ABSL_ENABLE_INSTALL = "ON",
          ABSL_PROPAGATE_CXX_STD = "ON",
          ABSL_BUILD_TEST_HELPERS = "OFF",
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
      libs = {},
      binaries = {},
    },
}
