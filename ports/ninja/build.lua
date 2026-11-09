-- ninja 1.12.1 -- ONE port, ONE build.lua + ONE features.yaml.
-- Ninja build tool, built from source with its stock CMake project.
-- Static checks in tests/r12.sh; GCPKG_R12_DYNAMIC=1 builds it for real.
-- Upstream is never patched: all adaptation lives in this file.

local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "ninja",
    version = "1.12.1",
    license = "Apache-2.0",
    homepage = "https://ninja-build.org",
    description = "Ninja build tool built from source as a tool port",
    source = {
        url = "https://codeload.github.com/ninja-build/ninja/tar.gz/refs/tags/v1.12.1",
        sha256 = "821bdff48a3f683bc4bb3b6f0b5fe7b2d647cf65d52aeb63328c91a6c6df285a",
        strip = 1,
    },
    dependencies = {},
    cmake = {
        defines = {
          CMAKE_BUILD_TYPE = "Release",
          CMAKE_INSTALL_LIBDIR = "lib",
          BUILD_TESTING = "OFF",
          NINJA_BUILD_BINARY = "ON",
        },
        args = {},
    },
    exports = {
        includes = {}, libdirs = {}, libs = {},
        binaries = { "@PREFIX@/bin" },
    },
}
