-- mp11 1.92.0 -- gcpkg port definition.
-- Boost.Mp11 C++11 metaprogramming headers; README carries the BSL-1.0 notice.

local recipe = require("gcpkg.recipe")

return recipe.header {
    name = "mp11",
    version = "1.92.0",
    license = "BSL-1.0",
    homepage = "https://github.com/boostorg/mp11",
    description = "Boost.Mp11 header-only C++11 metaprogramming library",
    source = {
        url = "https://codeload.github.com/boostorg/mp11/tar.gz/refs/tags/boost-1.92.0",
        sha256 = "a5754dc5ff9e7ff34119983889530e3ab8d8fb43ce2b4fea9c18673044df45d9",
        strip = 1,
    },
    dependencies = {},
    header = {
        headers = {
            { src = "include/boost/mp11.hpp", dst = "boost/mp11.hpp" },
            { src = "include/boost/mp11", dst = "boost/mp11" },
          },
        include = "boost/mp11.hpp",
        flags = {
            "-std=c++17",
          },
        license_files = {
            "README.md",
          },
    },
    exports = {
      includes = { "@PREFIX@/include" },
      libdirs = { "@LIBDIR@" },
      libs = {},
      binaries = {},
    },
}
