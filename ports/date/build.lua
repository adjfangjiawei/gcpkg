-- date 3.0.3 -- ONE library, ONE build.lua + ONE features.yaml.
-- Static registry checks in tests/r12.sh; GCPKG_R12_DYNAMIC=1 builds it for real.
-- Header-only C++ date/time library; tz library off.
-- Upstream is never patched: all adaptation lives in this file.

local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "date",
    version = "3.0.3",
    license = "MIT",
    homepage = "https://github.com/HowardHinnant/date",
    description = "Header-only C++ date and time-zone library",
    source = {
        url = "https://codeload.github.com/HowardHinnant/date/tar.gz/refs/tags/v3.0.3",
        sha256 = "30de45a34a2605cca33a993a9ea54e8f140f23b1caf1acf3c2fd436c42c7d942",
        strip = 1,
    },
    dependencies = {},
    cmake = {
        defines = {
          BUILD_TESTING = "OFF",
          CMAKE_BUILD_TYPE = "Release",
          CMAKE_INSTALL_LIBDIR = "lib",
          BUILD_SHARED_LIBS = "OFF",
          ENABLE_DATE_TESTING = "OFF",
          BUILD_TZ_LIB = "OFF",
          USE_SYSTEM_TZ_DB = "ON",
          ENABLE_DATE_INSTALL = "ON",
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
