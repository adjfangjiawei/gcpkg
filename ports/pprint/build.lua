-- pprint v0.9.1 -- gcpkg port definition.
-- Header-only C++ pretty printer.

local recipe = require("gcpkg.recipe")

return recipe.header {
    name = "pprint",
    version = "v0.9.1",
    license = "MIT",
    homepage = "https://github.com/p-ranav/pprint",
    description = "Header-only C++ pretty printer",
    source = {
        url = "https://codeload.github.com/p-ranav/pprint/tar.gz/refs/tags/v0.9.1",
        sha256 = "b9cc0d42f7be4abbb50b2e3b6a89589c5399201a3dc1fd7cfa72d412afdb2f86",
        strip = 1,
    },
    dependencies = {},
    header = {
        headers = {
            { src = "include/pprint.hpp", dst = "pprint.hpp" },
          },
        include = "pprint.hpp",
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
