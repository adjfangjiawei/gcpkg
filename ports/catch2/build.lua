-- catch2 3.7.1 -- ONE library, ONE build.lua + ONE features.yaml.
-- Verification: static registry/graph tests in tests/r10.sh; real
-- builds in GCPKG_R10_DYNAMIC=1 ./tests/r10.sh.
-- Catch2 v3: two static libs, self-tests off.
-- Upstream is never patched: all adaptation is in this file.

local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "catch2",
    version = "3.7.1",
    license = "BSL-1.0",
    homepage = "https://github.com/catchorg/Catch2",
    description = "Modern C++ unit-test framework",
    source = {
        url = "https://codeload.github.com/catchorg/Catch2/tar.gz/refs/tags/v3.7.1",
        sha256 = "c991b247a1a0d7bb9c39aa35faf0fe9e19764213f28ffba3109388e62ee0269c",
        strip = 1,
    },
    dependencies = {},
    cmake = {
        defines = {
          BUILD_TESTING = "OFF",
          CATCH_BUILD_TESTING = "OFF",
          CATCH_DEVELOPMENT_BUILD = "OFF",
          CATCH_INSTALL_DOCS = "OFF",
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
        "Catch2",
        "Catch2Main",
      },
      binaries = {},
    },
}
