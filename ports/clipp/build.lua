-- clipp 1.2.3 -- gcpkg port definition.
-- Header-only command-line argument parser.

local recipe = require("gcpkg.recipe")

return recipe.header {
    name = "clipp",
    version = "1.2.3",
    license = "MIT",
    homepage = "https://github.com/muellan/clipp",
    description = "Header-only command-line argument parser",
    source = {
        url = "https://codeload.github.com/muellan/clipp/tar.gz/refs/tags/v1.2.3",
        sha256 = "73da8e3d354fececdea99f7deb79d0343647349563ace3eafb7f4cca6e86e90b",
        strip = 1,
    },
    dependencies = {},
    header = {
        headers = {
            { src = "include/clipp.h", dst = "clipp.h" },
          },
        include = "clipp.h",
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
