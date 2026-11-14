-- ut 2.3.1 -- gcpkg port definition.
-- Boost-ext UT single-header C++20 unit testing framework.

local recipe = require("gcpkg.recipe")

return recipe.header {
    name = "ut",
    version = "2.3.1",
    license = "BSL-1.0",
    homepage = "https://github.com/boost-ext/ut",
    description = "Boost-ext UT header-only C++20 unit testing framework",
    source = {
        url = "https://codeload.github.com/boost-ext/ut/tar.gz/refs/tags/v2.3.1",
        sha256 = "e51bf1873705819730c3f9d2d397268d1c26128565478e2e65b7d0abb45ea9b1",
        strip = 1,
    },
    dependencies = {},
    header = {
        headers = {
            { src = "include/boost/ut.hpp", dst = "boost/ut.hpp" },
          },
        include = "boost/ut.hpp",
        flags = {
            "-std=c++20",
          },
        license_files = {
            "LICENSE.md",
          },
    },
    exports = {
      includes = { "@PREFIX@/include" },
      libdirs = { "@LIBDIR@" },
      libs = {},
      binaries = {},
    },
}
