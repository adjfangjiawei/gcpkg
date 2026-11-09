-- lzo 2.10 -- ONE library, ONE build.lua + ONE features.yaml.
-- Static registry checks in tests/r12.sh; GCPKG_R12_DYNAMIC=1 builds it for real.
-- LZO real-time compression library; CMake static build.
-- Upstream is never patched: all adaptation lives in this file.

local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "lzo",
    version = "2.10",
    license = "GPL-2.0-or-later",
    homepage = "https://www.oberhumer.com/opensource/lzo/",
    description = "Portable lossless data compression library",
    source = {
        url = "https://www.oberhumer.com/opensource/lzo/download/lzo-2.10.tar.gz",
        sha256 = "c0f892943208266f9b6543b3ae308fab6284c5c90e627931446fb49b4221a072",
        strip = 1,
    },
    dependencies = {},
    cmake = {
        defines = {
          BUILD_TESTING = "OFF",
          CMAKE_BUILD_TYPE = "Release",
          CMAKE_INSTALL_LIBDIR = "lib",
          BUILD_SHARED_LIBS = "OFF",
          ENABLE_STATIC = "ON",
          ENABLE_SHARED = "OFF",
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
        "lzo2",
      },
      binaries = {},
    },
}
