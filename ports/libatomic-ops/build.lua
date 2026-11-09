-- libatomic-ops 7.8.2 -- gcpkg port definition.
-- Atomic memory update primitives; static build.

local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "libatomic-ops",
    version = "7.8.2",
    license = "MIT",
    homepage = "https://github.com/ivmai/libatomic_ops",
    description = "Atomic memory update operations",
    source = {
        url = "https://codeload.github.com/ivmai/libatomic_ops/tar.gz/refs/tags/v7.8.2",
        sha256 = "ad8428a40e01d41bc4ddad3166afa1fc175c9e58d8ef7ddbd7ef3298e32ac37b",
        strip = 1,
    },
    dependencies = {},
    cmake = {
        defines = {
          BUILD_TESTING = "OFF",
          BUILD_SHARED_LIBS = "OFF",
          enable_gpl = "OFF",
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
        "atomic_ops",
      },
      binaries = {},
    },
}
