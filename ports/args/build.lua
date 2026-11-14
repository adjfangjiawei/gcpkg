-- args 6.6.1 -- gcpkg port definition.
-- Header-only C++ command-line argument parser.

local recipe = require("gcpkg.recipe")

return recipe.header {
    name = "args",
    version = "6.6.1",
    license = "MIT",
    homepage = "https://github.com/Taywee/args",
    description = "Header-only C++ command-line argument parser",
    source = {
        url = "https://codeload.github.com/Taywee/args/tar.gz/refs/tags/6.6.1",
        sha256 = "61cdbb13f55493e6ffe07018c86b17f9ff68a5c1059eb15f4f079e04429915ff",
        strip = 1,
    },
    dependencies = {},
    header = {
        headers = {
            { src = "args.hxx", dst = "args.hxx" },
          },
        include = "args.hxx",
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
