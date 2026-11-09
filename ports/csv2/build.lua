-- csv2 0.2 -- gcpkg port definition.
-- Amalgamated header-only CSV reader/writer plus bundled mio license.

local recipe = require("gcpkg.recipe")

return recipe.header {
    name = "csv2",
    version = "0.2",
    license = "MIT",
    homepage = "https://github.com/p-ranav/csv2",
    description = "Header-only C++17 CSV reader and writer",
    source = {
        url = "https://codeload.github.com/p-ranav/csv2/tar.gz/refs/tags/v0.2",
        sha256 = "30e9ac5e83520475a274ec04494ad24d602a15bb75839610b51432e50a98048d",
        strip = 1,
    },
    dependencies = {},
    header = {
        headers = {
            { src = "single_include/csv2/csv2.hpp", dst = "csv2/csv2.hpp" },
          },
        include = "csv2/csv2.hpp",
        flags = {
            "-std=c++17",
          },
        license_files = {
            "LICENSE",
            "LICENSE.mio",
          },
    },
    exports = {
      includes = { "@PREFIX@/include" },
      libdirs = { "@LIBDIR@" },
      libs = {},
      binaries = {},
    },
}
