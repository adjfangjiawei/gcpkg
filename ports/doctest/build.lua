-- doctest 2.4.11 -- ONE library, ONE build.lua + ONE features.yaml.
-- Verification: static registry/graph tests in tests/r10.sh; real
-- builds in GCPKG_R10_DYNAMIC=1 ./tests/r10.sh.
-- Header-only C++ test framework: headers only.
-- Upstream is never patched: all adaptation is in this file.

local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "doctest",
    version = "2.4.11",
    license = "MIT",
    homepage = "https://github.com/doctest/doctest",
    description = "Fast header-only C++ test framework",
    source = {
        url = "https://codeload.github.com/doctest/doctest/tar.gz/refs/tags/v2.4.11",
        sha256 = "632ed2c05a7f53fa961381497bf8069093f0d6628c5f26286161fbd32a560186",
        strip = 1,
    },
    dependencies = {},
    cmake = {
        defines = {
          BUILD_TESTING = "OFF",
          DOCTEST_WITH_TESTS = "OFF",
          DOCTEST_WITH_MAIN_IN_STATIC_LIB = "OFF",
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
