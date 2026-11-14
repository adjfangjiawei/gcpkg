-- sparse-map 0.7.0 -- gcpkg port definition.
-- Header-only sparse hash map and set.

local recipe = require("gcpkg.recipe")

return recipe.header {
    name = "sparse-map",
    version = "0.7.0",
    license = "MIT",
    homepage = "https://github.com/Tessil/sparse-map",
    description = "Header-only sparse hash map and set",
    source = {
        url = "https://codeload.github.com/Tessil/sparse-map/tar.gz/refs/tags/v0.7.0",
        sha256 = "b603a24f596f95a06ec1d437f4cb928c2647cf9bc73b751ac6fb82deb7863d98",
        strip = 1,
    },
    dependencies = {},
    header = {
        headers = {
            { src = "include/tsl", dst = "tsl" },
          },
        include = "tsl/sparse_map.h",
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
