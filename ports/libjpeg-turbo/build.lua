-- libjpeg-turbo 3.2.1 -- ONE library, ONE build.lua + ONE features.yaml.
-- Verification: static registry/graph tests here; real builds for a
-- subset live in tests/linux-base.sh (GCPKG_BASE_DYNAMIC=1).
-- SIMD JPEG codec; CMake build.
-- Upstream is never patched: all adaptation is in this file.

local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "libjpeg-turbo",
    version = "3.2.1",
    license = "BSD-3-Clause/IJG",
    homepage = "https://libjpeg-turbo.org",
    description = "SIMD-accelerated JPEG codec",
    source = {
        url = "https://codeload.github.com/libjpeg-turbo/libjpeg-turbo/tar.gz/refs/tags/3.2.1",
        sha256 = "6f5819c51649bce2571a23b1b0cd41eae2f57fc3f8908c7ec9e7047efb65ca13",
        strip = 1,
    },
    dependencies = {},
    cmake = {
        defines = {
          WITH_TESTS = "OFF",
          WITH_TOOLS = "OFF",
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
        "jpeg",
        "turbojpeg",
      },
      binaries = {},
    },
}
