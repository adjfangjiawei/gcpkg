-- libeconf 0.7.5 -- ONE library, ONE build.lua + ONE features.yaml.
-- Verification: static registry/graph tests in tests/r10.sh; real
-- builds in GCPKG_R10_DYNAMIC=1 ./tests/r10.sh.
-- openSUSE /etc config file parser; CMake.
-- Upstream is never patched: all adaptation is in this file.

local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "libeconf",
    version = "0.7.5",
    license = "MIT",
    homepage = "https://github.com/openSUSE/libeconf",
    description = "Configuration file parser for /etc and /usr",
    source = {
        url = "https://codeload.github.com/openSUSE/libeconf/tar.gz/refs/tags/v0.7.5",
        sha256 = "f78fe2ad7b2c8894f459e4e678acdbbdbf8a8c8453eb90257b1dfa674e6a08da",
        strip = 1,
    },
    dependencies = {},
    cmake = {
        defines = {
          BUILD_TESTING = "OFF",
          ENABLE_TESTS = "OFF",
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
        "econf",
      },
      binaries = {},
    },
}
