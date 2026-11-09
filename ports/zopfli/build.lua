-- zopfli 1.0.3 -- gcpkg port definition.
-- DEFLATE encoder; CMake.

local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "zopfli",
    version = "1.0.3",
    license = "Apache-2.0",
    homepage = "https://github.com/google/zopfli",
    description = "Very small DEFLATE/gzip/zlib encoder",
    source = {
        url = "https://codeload.github.com/google/zopfli/tar.gz/refs/tags/zopfli-1.0.3",
        sha256 = "e955a7739f71af37ef3349c4fa141c648e8775bceb2195be07e86f8e638814bd",
        strip = 1,
    },
    dependencies = {},
    cmake = {
        defines = {
          BUILD_TESTING = "OFF",
          ZOPFLI_BUILD_TOOLS = "OFF",
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
        "zopfli",
      },
      binaries = {},
    },
}
