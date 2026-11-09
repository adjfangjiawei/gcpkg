-- bitsery 5.2.5 -- gcpkg port definition.
-- Header-only binary serialization; whole bitsery/ tree installed.

local recipe = require("gcpkg.recipe")

return recipe.header {
    name = "bitsery",
    version = "5.2.5",
    license = "MIT",
    homepage = "https://github.com/fraillt/bitsery",
    description = "Header-only C++ binary serialization library",
    source = {
        url = "https://codeload.github.com/fraillt/bitsery/tar.gz/refs/tags/v5.2.5",
        sha256 = "22a6d92ac030e999b53d57a0c9afe28723766595c6d00c91ab9c5637d4ed0eec",
        strip = 1,
    },
    dependencies = {},
    header = {
        headers = {
            { src = "include/bitsery", dst = "bitsery" },
          },
        include = "bitsery/bitsery.h",
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
