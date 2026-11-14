-- argh 1.3.2 -- gcpkg port definition.
-- Header-only minimalist command-line argument parser.

local recipe = require("gcpkg.recipe")

return recipe.header {
    name = "argh",
    version = "1.3.2",
    license = "BSD-3-Clause",
    homepage = "https://github.com/adishavit/argh",
    description = "Header-only minimalist command-line argument parser",
    source = {
        url = "https://codeload.github.com/adishavit/argh/tar.gz/refs/tags/v1.3.2",
        sha256 = "4b76d8c55e97cc0752feee4f00b99dc58464dd030dea9ba257c0a7d24a84f9dd",
        strip = 1,
    },
    dependencies = {},
    header = {
        headers = {
            { src = "argh.h", dst = "argh.h" },
          },
        include = "argh.h",
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
