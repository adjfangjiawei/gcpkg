-- zlib-ng 2.2.4 -- ONE library, ONE build.lua + ONE features.yaml.
-- Verification: static registry/graph tests here; real builds for a
-- subset live in tests/extra.sh (GCPKG_EXTRA_DYNAMIC=1).
-- zlib-ng in zlib-compat mode; all three test switches must be OFF.
-- Upstream is never patched: all adaptation is in this file.

local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "zlib-ng",
    version = "2.2.4",
    license = "Zlib",
    homepage = "https://github.com/zlib-ng/zlib-ng",
    description = "zlib replacement with SIMD optimisations",
    source = {
        url = "https://codeload.github.com/zlib-ng/zlib-ng/tar.gz/refs/tags/2.2.4",
        sha256 = "a73343c3093e5cdc50d9377997c3815b878fd110bf6511c2c7759f2afb90f5a3",
        strip = 1,
    },
    dependencies = {},
    cmake = {
        defines = {
          ZLIB_COMPAT = "ON",
          ZLIBNG_ENABLE_TESTS = "OFF",
          ZLIB_ENABLE_TESTS = "OFF",
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
        "z",
      },
      binaries = {},
    },
}
