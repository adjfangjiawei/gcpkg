-- maddy 1.6.0 -- gcpkg port definition.
-- Header-only C++ Markdown parser; whole maddy/ tree installed.

local recipe = require("gcpkg.recipe")

return recipe.header {
    name = "maddy",
    version = "1.6.0",
    license = "MIT",
    homepage = "https://github.com/progsource/maddy",
    description = "Header-only C++ Markdown parser",
    source = {
        url = "https://codeload.github.com/progsource/maddy/tar.gz/refs/tags/1.6.0",
        sha256 = "811b19efbc2fbf1957486ed78aabaf5d164d15f84464f7b4a7033b44591845c5",
        strip = 1,
    },
    dependencies = {},
    header = {
        headers = {
            { src = "include/maddy", dst = "maddy" },
          },
        include = "maddy/parser.h",
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
