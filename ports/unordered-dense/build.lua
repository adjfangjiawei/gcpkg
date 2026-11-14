-- unordered-dense 4.8.0 -- gcpkg port definition.
-- Header-only robin-hood hash map/set.

local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "unordered-dense",
    version = "4.8.0",
    license = "MIT",
    homepage = "https://github.com/martinus/unordered_dense",
    description = "Fast header-only robin-hood hash map and set",
    source = {
        url = "https://codeload.github.com/martinus/unordered_dense/tar.gz/refs/tags/v4.8.0",
        sha256 = "29214a96de12959d8d0342a235c26d6f246c3f3e75f4bc135b6e784753513ead",
        strip = 1,
    },
    dependencies = {},
    cmake = {
        defines = {
          BUILD_TESTING = "OFF",
          CMAKE_BUILD_TYPE = "Release",
          CMAKE_INSTALL_LIBDIR = "lib",
          BUILD_SHARED_LIBS = "OFF",
          ANKERL_ENABLE_MODULES = "OFF",
          ANKERL_ENABLE_EXAMPLE = "OFF",
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
