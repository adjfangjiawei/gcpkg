-- robin-hood-hashing 3.11.5 -- gcpkg port definition.
-- Header-only robin-hood hash map and set.

local recipe = require("gcpkg.recipe")

return recipe.header {
    name = "robin-hood-hashing",
    version = "3.11.5",
    license = "MIT",
    homepage = "https://github.com/martinus/robin-hood-hashing",
    description = "Header-only robin-hood hash map and set",
    source = {
        url = "https://codeload.github.com/martinus/robin-hood-hashing/tar.gz/refs/tags/3.11.5",
        sha256 = "3693e44dda569e9a8b87ce8263f7477b23af448a3c3600c8ab9004fe79c20ad0",
        strip = 1,
    },
    dependencies = {},
    header = {
        headers = {
            { src = "src/include/robin_hood.h", dst = "robin_hood.h" },
          },
        include = "robin_hood.h",
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
