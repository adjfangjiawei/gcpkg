-- hopscotch-map v2.3.1 -- gcpkg port definition.
-- Header-only hopscotch hash map and set.

local recipe = require("gcpkg.recipe")

return recipe.header {
    name = "hopscotch-map",
    version = "v2.3.1",
    license = "MIT",
    homepage = "https://github.com/Tessil/hopscotch-map",
    description = "Fast header-only hash map and set",
    source = {
        url = "https://codeload.github.com/Tessil/hopscotch-map/tar.gz/refs/tags/v2.3.1",
        sha256 = "53dab49005cd5dc859f2546d0d3eef058ec7fb3b74fc3b19f4965a9a151e9b20",
        strip = 1,
    },
    dependencies = {},
    header = {
        headers = {
            { src = "include/tsl", dst = "tsl" },
          },
        include = "tsl/hopscotch_map.h",
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
