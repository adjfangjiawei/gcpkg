-- sol2 3.5.0 -- gcpkg port definition.
-- Header-only C++ Lua bindings; depends on the lua port.

local recipe = require("gcpkg.recipe")

return recipe.header {
    name = "sol2",
    version = "3.5.0",
    license = "MIT",
    homepage = "https://github.com/ThePhD/sol2",
    description = "Header-only C++ Lua binding library",
    source = {
        url = "https://codeload.github.com/ThePhD/sol2/tar.gz/refs/tags/v3.5.0",
        sha256 = "86c0f6d2836b184a250fc2907091c076bf53c9603dd291eaebade36cc342e13c",
        strip = 1,
    },
    dependencies = {
        "lua",
      },
    header = {
        headers = {
            { src = "include/sol", dst = "sol" },
          },
        include = "sol/sol.hpp",
        flags = {
            "-std=c++17",
          },
        license_files = {
            "LICENSE.txt",
          },
    },
    exports = {
      includes = { "@PREFIX@/include" },
      libdirs = { "@LIBDIR@" },
      libs = {},
      binaries = {},
    },
}
