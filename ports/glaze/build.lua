-- glaze 9.1.0 -- gcpkg port definition.
-- Header-only C++23 JSON and binary serialization; probe uses -std=c++23.

local recipe = require("gcpkg.recipe")

return recipe.header {
    name = "glaze",
    version = "9.1.0",
    license = "MIT",
    homepage = "https://github.com/stephenberry/glaze",
    description = "Header-only C++23 JSON and binary serialization library",
    source = {
        url = "https://codeload.github.com/stephenberry/glaze/tar.gz/refs/tags/v9.1.0",
        sha256 = "55f8a675397c505f9bee6c160e1c26b0085868f185d04d7a7727531fdbff4bd4",
        strip = 1,
    },
    dependencies = {},
    header = {
        headers = {
            { src = "include/glaze", dst = "glaze" },
          },
        include = "glaze/glaze.hpp",
        flags = {
            "-std=c++23",
          },
        license_files = {
            "LICENSE",
          },
    },
    exports = {
      includes = { "@PREFIX@/include" },
      libdirs = { "@LIBDIR@" },
      libs = {},
      binaries = {},
    },
}
