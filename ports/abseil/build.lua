-- abseil 20240722.0 -- gcpkg port definition.
-- Abseil C++ foundation: CMake package config installed for re2.

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
        -- Explicit results, like ports/sdl3/build.lua: every build knob and
        -- every feature-test result is stated here, so configure never probes.
        defines = {
          BUILD_TESTING = "OFF",
          BUILD_SHARED_LIBS = "OFF",
          ABSL_ENABLE_INSTALL = "ON",
          ABSL_PROPAGATE_CXX_STD = "ON",
          ABSL_BUILD_TESTING = "OFF",
          ABSL_BUILD_TEST_HELPERS = "OFF",
          ABSL_USE_EXTERNAL_GOOGLETEST = "OFF",
          ABSL_FIND_GOOGLETEST = "OFF",
          ABSL_USE_GOOGLETEST_HEAD = "OFF",
          ABSL_BUILD_MONOLITHIC_SHARED_LIBS = "OFF",
          ABSL_USE_SYSTEM_INCLUDES = "OFF",
          ABSL_MSVC_STATIC_RUNTIME = "OFF",
          -- AbseilDll.cmake check_cxx_source_compiles results.  clang-23 is
          -- used without -std=c++20; state both explicitly instead of probing.
          ABSL_INTERNAL_AT_LEAST_CXX17 = "FALSE",
          ABSL_INTERNAL_AT_LEAST_CXX20 = "FALSE",
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
