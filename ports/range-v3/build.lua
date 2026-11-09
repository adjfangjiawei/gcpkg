-- range-v3 0.12.0 -- ONE library, ONE build.lua + ONE features.yaml.
-- Static registry checks in tests/r12.sh; GCPKG_R12_DYNAMIC=1 builds it for real.
-- Header-only C++ ranges; tests/examples/docs disabled.
-- Upstream is never patched: all adaptation lives in this file.

local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "range-v3",
    version = "0.12.0",
    license = "BSL-1.0",
    homepage = "https://github.com/ericniebler/range-v3",
    description = "Header-only C++ ranges library",
    source = {
        url = "https://codeload.github.com/ericniebler/range-v3/tar.gz/refs/tags/0.12.0",
        sha256 = "015adb2300a98edfceaf0725beec3337f542af4915cec4d0b89fa0886f4ba9cb",
        strip = 1,
    },
    dependencies = {},
    cmake = {
        defines = {
          BUILD_TESTING = "OFF",
          CMAKE_BUILD_TYPE = "Release",
          CMAKE_INSTALL_LIBDIR = "lib",
          BUILD_SHARED_LIBS = "OFF",
          RANGE_V3_TESTS = "OFF",
          RANGE_V3_EXAMPLES = "OFF",
          RANGE_V3_DOCS = "OFF",
          RANGE_V3_PERF = "OFF",
          RANGES_BUILD_CALENDAR_EXAMPLE = "OFF",
          RANGES_NATIVE = "OFF",
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
