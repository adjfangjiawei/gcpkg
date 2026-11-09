-- tabulate v2.2 -- gcpkg port definition.
-- Header-only table formatter; bundled lite licenses installed.

local recipe = require("gcpkg.recipe")

return recipe.header {
    name = "tabulate",
    version = "v2.2",
    license = "MIT",
    homepage = "https://github.com/p-ranav/tabulate",
    description = "Header-only C++ table formatting library",
    source = {
        url = "https://codeload.github.com/p-ranav/tabulate/tar.gz/refs/tags/v2.2",
        sha256 = "3c12853cbf103adf659c4821351a302351d139513f1c43528095da41e8a37044",
        strip = 1,
    },
    dependencies = {},
    header = {
        headers = {
            { src = "include/tabulate", dst = "tabulate" },
          },
        include = "tabulate/tabulate.hpp",
        flags = {
            "-std=c++17",
          },
        license_files = {
            "LICENSE",
            "LICENSE.optional-lite",
            "LICENSE.termcolor",
            "LICENSE.variant-lite",
          },
    },
    exports = {
      includes = { "@PREFIX@/include" },
      libdirs = { "@LIBDIR@" },
      libs = {},
      binaries = {},
    },
}
