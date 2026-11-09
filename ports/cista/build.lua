-- cista 0.16 -- gcpkg port definition.
-- Zero-copy serialization containers; whole cista/ tree installed.

local recipe = require("gcpkg.recipe")

return recipe.header {
    name = "cista",
    version = "0.16",
    license = "MIT",
    homepage = "https://github.com/felixguendling/cista",
    description = "Header-only C++ zero-copy serialization containers",
    source = {
        url = "https://codeload.github.com/felixguendling/cista/tar.gz/refs/tags/v0.16",
        sha256 = "55832c0e723568bd3abdfd70e7ba4dca777dfaada63f4da74f325f868f95694e",
        strip = 1,
    },
    dependencies = {},
    header = {
        headers = {
            { src = "include/cista", dst = "cista" },
          },
        include = "cista/containers.h",
        flags = {
            "-std=c++20",
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
