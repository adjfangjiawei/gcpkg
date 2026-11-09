-- lyra 1.7.0 -- gcpkg port definition.
-- Header-only CLI parser; whole lyra/ tree installed.

local recipe = require("gcpkg.recipe")

return recipe.header {
    name = "lyra",
    version = "1.7.0",
    license = "BSL-1.0",
    homepage = "https://github.com/bfgroup/Lyra",
    description = "Header-only command-line argument parser",
    source = {
        url = "https://codeload.github.com/bfgroup/Lyra/tar.gz/refs/tags/1.7.0",
        sha256 = "d26b9e9dc1e08f88feaebc68965a6e5b25c7cd88617ce910d47cc83efb1e07d9",
        strip = 1,
    },
    dependencies = {},
    header = {
        headers = {
            { src = "include/lyra", dst = "lyra" },
          },
        include = "lyra/lyra.hpp",
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
