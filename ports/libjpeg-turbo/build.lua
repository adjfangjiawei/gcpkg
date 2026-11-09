-- libjpeg-turbo 3.2.1 -- gcpkg port definition.
-- SIMD JPEG codec; CMake build.

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
