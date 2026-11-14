-- jansson 2.15.1 -- gcpkg port definition.
-- JSON C library; complements the existing json-c port.

local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "jansson",
    version = "2.15.1",
    license = "MIT",
    homepage = "https://github.com/akheron/jansson",
    description = "C library for encoding/decoding JSON",
    source = {
        url = "https://codeload.github.com/akheron/jansson/tar.gz/refs/tags/v2.15.1",
        sha256 = "dbf95cb0af903f4fb8b61507d96b45b67db7d1479688ede352e1d571394d06f7",
        strip = 1,
    },
    dependencies = {},
    cmake = {
        defines = {
          JANSSON_BUILD_DOCS = "OFF",
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
        "jansson",
      },
      binaries = {},
    },
}
