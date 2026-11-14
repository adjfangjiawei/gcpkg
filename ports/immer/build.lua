-- immer 0.9.1 -- gcpkg port definition.
-- Header-only immutable and persistent data structures.

local recipe = require("gcpkg.recipe")

return recipe.header {
    name = "immer",
    version = "0.9.1",
    license = "BSL-1.0",
    homepage = "https://github.com/arximboldi/immer",
    description = "Header-only immutable and persistent data structures",
    source = {
        url = "https://codeload.github.com/arximboldi/immer/tar.gz/refs/tags/v0.9.1",
        sha256 = "b18b92ba60ec3186dc36ef671d3c2ae542cbb63eb6dc0e258476c6111a67c971",
        strip = 1,
    },
    dependencies = {},
    header = {
        headers = {
            { src = "immer", dst = "immer" },
          },
        include = "immer/vector.hpp",
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
