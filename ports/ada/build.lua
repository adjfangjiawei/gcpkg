-- ada 2.9.2 -- gcpkg port definition.
-- WHATWG URL parser (C++20).

local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "ada",
    version = "2.9.2",
    license = "Apache-2.0",
    homepage = "https://github.com/ada-url/ada",
    description = "Fast WHATWG-compliant URL parser",
    source = {
        url = "https://codeload.github.com/ada-url/ada/tar.gz/refs/tags/v2.9.2",
        sha256 = "f41575ad7eec833afd9f6a0d6101ee7dc2f947fdf19ae8f1b54a71d59f4ba5ec",
        strip = 1,
    },
    dependencies = {},
    cmake = {
        defines = {
          BUILD_TESTING = "OFF",
          ADA_TESTING = "OFF",
          ADA_BENCHMARKS = "OFF",
          BUILD_SHARED_LIBS = "OFF",
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
        "ada",
      },
      binaries = {},
    },
}
