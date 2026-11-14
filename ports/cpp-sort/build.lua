-- cpp-sort 1.17.0 -- gcpkg port definition.
-- Header-only C++ sorting algorithms.

local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "cpp-sort",
    version = "1.17.0",
    license = "MIT",
    homepage = "https://github.com/Morwenn/cpp-sort",
    description = "Header-only C++ sorting algorithms",
    source = {
        url = "https://codeload.github.com/Morwenn/cpp-sort/tar.gz/refs/tags/1.17.0",
        sha256 = "df6cbb805ff71e1b0a30fc1ed55696a2d8c70c3ab87447bee2b749e02415432e",
        strip = 1,
    },
    dependencies = {},
    cmake = {
        defines = {
          BUILD_TESTING = "OFF",
          CMAKE_BUILD_TYPE = "Release",
          CMAKE_INSTALL_LIBDIR = "lib",
          BUILD_SHARED_LIBS = "OFF",
          CPPSORT_BUILD_TESTING = "OFF",
          CPPSORT_BUILD_EXAMPLES = "OFF",
          CPPSORT_USE_LIBASSERT = "OFF",
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
