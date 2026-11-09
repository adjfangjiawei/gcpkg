-- openjpeg 2.5.3 -- ONE library, ONE build.lua + ONE features.yaml.
-- Static registry checks in tests/r12.sh; GCPKG_R12_DYNAMIC=1 builds it for real.
-- OpenJPEG JPEG-2000 codec; static library only.
-- Upstream is never patched: all adaptation lives in this file.

local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "openjpeg",
    version = "2.5.3",
    license = "BSD-2-Clause",
    homepage = "https://www.openjpeg.org",
    description = "JPEG 2000 codec library",
    source = {
        url = "https://codeload.github.com/uclouvain/openjpeg/tar.gz/refs/tags/v2.5.3",
        sha256 = "368fe0468228e767433c9ebdea82ad9d801a3ad1e4234421f352c8b06e7aa707",
        strip = 1,
    },
    dependencies = {},
    cmake = {
        defines = {
          BUILD_TESTING = "OFF",
          CMAKE_BUILD_TYPE = "Release",
          CMAKE_INSTALL_LIBDIR = "lib",
          BUILD_SHARED_LIBS = "OFF",
          BUILD_STATIC_LIBS = "ON",
          BUILD_CODEC = "OFF",
          BUILD_UNIT_TESTS = "OFF",
          BUILD_DOC = "OFF",
          BUILD_JPIP = "OFF",
          BUILD_VIEWER = "OFF",
          BUILD_JAVA = "OFF",
          BUILD_THIRDPARTY = "OFF",
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
        "openjp2",
      },
      binaries = {},
    },
}
