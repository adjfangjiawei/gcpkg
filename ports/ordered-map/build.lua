-- ordered-map 1.2.0 -- gcpkg port definition.
-- Header-only insertion-order preserving hash map and set.

local recipe = require("gcpkg.recipe")

return recipe.header {
    name = "ordered-map",
    version = "1.2.0",
    license = "MIT",
    homepage = "https://github.com/Tessil/ordered-map",
    description = "Header-only insertion-order preserving hash map and set",
    source = {
        url = "https://codeload.github.com/Tessil/ordered-map/tar.gz/refs/tags/v1.2.0",
        sha256 = "3053e2d62db8a158c5941b75dacf397e1c695cd99dda4db78a32af76f4523423",
        strip = 1,
    },
    dependencies = {},
    header = {
        headers = {
            { src = "include/tsl", dst = "tsl" },
          },
        include = "tsl/ordered_map.h",
        flags = {
            "-std=c++17",
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
