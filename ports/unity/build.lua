-- unity 2.6.0 -- ONE library, ONE build.lua + ONE features.yaml.
-- Static registry checks in tests/r12.sh; GCPKG_R12_DYNAMIC=1 builds it for real.
-- Unity C test framework; static library and headers.
-- Upstream is never patched: all adaptation lives in this file.

local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "unity",
    version = "2.6.0",
    license = "MIT",
    homepage = "https://github.com/ThrowTheSwitch/Unity",
    description = "Embedded C unit test framework",
    source = {
        url = "https://codeload.github.com/ThrowTheSwitch/Unity/tar.gz/refs/tags/v2.6.0",
        sha256 = "aa4c9fb1ae5fc5242f914c65f3557e817e40cb37f04a31e5ff76d1ab89dbf674",
        strip = 1,
    },
    dependencies = {},
    cmake = {
        defines = {
          BUILD_TESTING = "OFF",
          CMAKE_BUILD_TYPE = "Release",
          CMAKE_INSTALL_LIBDIR = "lib",
          BUILD_SHARED_LIBS = "OFF",
          UNITY_EXTENSION_FIXTURE = "OFF",
          UNITY_EXTENSION_MEMORY = "OFF",
        },
        args = {},
    },
    exports = {
      includes = {
        "@PREFIX@/include",
        "@PREFIX@/include/unity",
      },
      libdirs = {
        "@LIBDIR@",
      },
      libs = {
        "unity",
      },
      binaries = {},
    },
}
