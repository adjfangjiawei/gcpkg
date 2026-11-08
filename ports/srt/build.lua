-- srt 1.5.4 -- ONE library, ONE build.lua + ONE features.yaml.
-- Verification: static registry/graph tests in tests/r10.sh; real
-- builds in GCPKG_R10_DYNAMIC=1 ./tests/r10.sh.
-- Secure Reliable Transport; encryption off by default, `tls` feature adds openssl.
-- Upstream is never patched: all adaptation is in this file.

local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "srt",
    version = "1.5.4",
    license = "MPL-2.0",
    homepage = "https://github.com/Haivision/srt",
    description = "Secure Reliable Transport (low-latency video)",
    source = {
        url = "https://codeload.github.com/Haivision/srt/tar.gz/refs/tags/v1.5.4",
        sha256 = "d0a8b600fe1b4eaaf6277530e3cfc8f15b8ce4035f16af4a5eb5d4b123640cdd",
        strip = 1,
    },
    dependencies = {},
    cmake = {
        defines = {
          ENABLE_APPS = "OFF",
          ENABLE_TESTING = "OFF",
          ENABLE_ENCRYPTION = "OFF",
          ENABLE_SHARED = "OFF",
          ENABLE_STATIC = "ON",
          ENABLE_UNITTESTS = "OFF",
          ENABLE_CXX11 = "OFF",
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
        "srt",
      },
      binaries = {},
    },
}
