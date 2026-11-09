-- indicators v2.3 -- gcpkg port definition.
-- Bundled single-header progress bars; cstdint prelude fixes upstream 2.3.

local recipe = require("gcpkg.recipe")

return recipe.header {
    name = "indicators",
    version = "v2.3",
    license = "MIT",
    homepage = "https://github.com/p-ranav/indicators",
    description = "Header-only C++ progress bars and indicators",
    source = {
        url = "https://codeload.github.com/p-ranav/indicators/tar.gz/refs/tags/v2.3",
        sha256 = "70da7a693ff7a6a283850ab6d62acf628eea17d386488af8918576d0760aef7b",
        strip = 1,
    },
    dependencies = {},
    header = {
        headers = {
            { src = "single_include/indicators", dst = "indicators" },
          },
        include = "indicators/indicators.hpp",
        prelude = {
            "cstdint",
          },
        flags = {
            "-std=c++17",
          },
        license_files = {
            "LICENSE",
            "LICENSE.termcolor",
          },
    },
    exports = {
      includes = { "@PREFIX@/include" },
      libdirs = { "@LIBDIR@" },
      libs = {},
      binaries = {},
    },
}
