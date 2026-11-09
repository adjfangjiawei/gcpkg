-- mimalloc 2.1.2 -- gcpkg port definition.
-- Microsoft mimalloc allocator; static library.

local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "mimalloc",
    version = "2.1.2",
    license = "MIT",
    homepage = "https://github.com/microsoft/mimalloc",
    description = "Compact general-purpose allocator",
    source = {
        url = "https://codeload.github.com/microsoft/mimalloc/tar.gz/refs/tags/v2.1.2",
        sha256 = "2b1bff6f717f9725c70bf8d79e4786da13de8a270059e4ba0bdd262ae7be46eb",
        strip = 1,
    },
    dependencies = {},
    cmake = {
        defines = {
          BUILD_TESTING = "OFF",
          MI_BUILD_TESTS = "OFF",
          MI_BUILD_SHARED = "OFF",
          MI_BUILD_STATIC = "ON",
          MI_BUILD_OBJECT = "OFF",
          MI_INSTALL_TOPLEVEL = "ON",
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
        "mimalloc",
      },
      binaries = {},
    },
}
