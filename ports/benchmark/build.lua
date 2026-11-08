-- benchmark 1.9.1 -- ONE library, ONE build.lua + ONE features.yaml.
-- Verification: static registry/graph tests in tests/r10.sh; real
-- builds in GCPKG_R10_DYNAMIC=1 ./tests/r10.sh.
-- Google microbenchmark library; no bundled googletest.
-- Upstream is never patched: all adaptation is in this file.

local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "benchmark",
    version = "1.9.1",
    license = "Apache-2.0",
    homepage = "https://github.com/google/benchmark",
    description = "Google microbenchmark support library",
    source = {
        url = "https://codeload.github.com/google/benchmark/tar.gz/refs/tags/v1.9.1",
        sha256 = "32131c08ee31eeff2c8968d7e874f3cb648034377dfc32a4c377fa8796d84981",
        strip = 1,
    },
    dependencies = {},
    cmake = {
        defines = {
          BUILD_TESTING = "OFF",
          BENCHMARK_ENABLE_TESTING = "OFF",
          BENCHMARK_ENABLE_GTEST_TESTS = "OFF",
          BENCHMARK_ENABLE_LIBPFM = "OFF",
          BENCHMARK_ENABLE_INSTALL = "ON",
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
        "benchmark",
        "benchmark_main",
      },
      binaries = {},
    },
}
