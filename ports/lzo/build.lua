-- lzo 2.10 -- gcpkg port definition.
-- LZO real-time compression library; CMake static build.
--
-- R20: platform facts (byte order, sizeof, headers, functions) are NOT
-- hardcoded here.  gcpkg probes the active triplet ONCE at the start of each
-- install task and injects that one shared fact table into every port's
-- short-circuited check_* macros.  Switching triplet / OS / CPU needs no port
-- edit: user settings in <store>/.gcpkg/config.yaml (facts:) win over probes,
-- and the probe itself adapts to the selected compiler.  Zero library probes.
--
-- NOTE: static/shared are mutually exclusive build shapes, not features; the
-- functional feature gates are reviewed port-by-port starting from P1.

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
      includes = { "@PREFIX@/include" },
      libdirs = { "@LIBDIR@" },
      libs = { "lzo2" },
      binaries = {},
    },
}
