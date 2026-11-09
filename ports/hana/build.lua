-- hana 1.7.0 -- gcpkg port definition.
-- Boost.Hana metaprogramming headers installed under boost/hana.

local recipe = require("gcpkg.recipe")

return recipe.header {
    name = "hana",
    version = "1.7.0",
    license = "BSL-1.0",
    homepage = "https://github.com/boostorg/hana",
    description = "Boost.Hana header-only metaprogramming library",
    source = {
        url = "https://codeload.github.com/boostorg/hana/tar.gz/refs/tags/v1.7.0",
        sha256 = "f228013dc32acf69e30c2200964c96b119a6e779817b24457c76096bb57e1280",
        strip = 1,
    },
    dependencies = {},
    header = {
        headers = {
            { src = "include/boost/hana.hpp", dst = "boost/hana.hpp" },
            { src = "include/boost/hana", dst = "boost/hana" },
          },
        include = "boost/hana.hpp",
        flags = {
            "-std=c++17",
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
