-- libbase64 0.5.2 -- ONE library, ONE build.lua + ONE features.yaml.
-- Verification: static registry/graph tests here; real builds for a
-- subset live in tests/extra.sh (GCPKG_EXTRA_DYNAMIC=1).
-- SIMD base64 codec; CMake (also ships a hand-written Makefile).
-- Upstream is never patched: all adaptation is in this file.

local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "libbase64",
    version = "0.5.2",
    license = "BSD-2-Clause",
    homepage = "https://github.com/aklomp/base64",
    description = "SIMD-accelerated base64 codec",
    source = {
        url = "https://codeload.github.com/aklomp/base64/tar.gz/refs/tags/v0.5.2",
        sha256 = "723a0f9f4cf44cf79e97bcc315ec8f85e52eb104c8882942c3f2fba95acc080d",
        strip = 1,
    },
    dependencies = {},
    cmake = {
        defines = {
          BUILD_TESTING = "OFF",
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
        "base64",
      },
      binaries = {},
    },
}
