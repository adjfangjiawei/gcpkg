-- benchmark 1.9.1 -- gcpkg port definition.
-- Google microbenchmark library; no bundled googletest.

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
        -- Explicit results, like ports/sdl3/build.lua.  CXXFeatureCheck.cmake
        -- uses try_run() probes; HAVE_STD_REGEX makes it take its DEFINED fast
        -- path, and the remaining feature checks are short-circuited by the
        -- global try_run override.  Every build knob is stated here too.
        defines = {
          BUILD_TESTING = "OFF",
          BUILD_SHARED_LIBS = "OFF",
          CMAKE_BUILD_TYPE = "Release",
          CMAKE_CXX_STANDARD = "17",
          BENCHMARK_ENABLE_TESTING = "OFF",
          BENCHMARK_ENABLE_GTEST_TESTS = "OFF",
          BENCHMARK_USE_BUNDLED_GTEST = "ON",
          BENCHMARK_ENABLE_EXCEPTIONS = "ON",
          BENCHMARK_ENABLE_LTO = "OFF",
          BENCHMARK_USE_LIBCXX = "OFF",
          BENCHMARK_ENABLE_WERROR = "OFF",
          BENCHMARK_FORCE_WERROR = "OFF",
          BENCHMARK_ENABLE_INSTALL = "ON",
          BENCHMARK_ENABLE_DOXYGEN = "OFF",
          BENCHMARK_INSTALL_DOCS = "OFF",
          BENCHMARK_DOWNLOAD_DEPENDENCIES = "OFF",
          BENCHMARK_ENABLE_LIBPFM = "OFF",
          BENCHMARK_ENABLE_ASSEMBLY_TESTS = "OFF",
          CXXFEATURECHECK_DEBUG = "OFF",
          HAVE_STD_REGEX = "TRUE",
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
