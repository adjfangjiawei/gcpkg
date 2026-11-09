-- describe 1.92.0 -- gcpkg port definition.
-- Boost.Describe reflection headers; depends on mp11.

local recipe = require("gcpkg.recipe")

return recipe.header {
    name = "describe",
    version = "1.92.0",
    license = "BSL-1.0",
    homepage = "https://github.com/boostorg/describe",
    description = "Boost.Describe header-only class/enum reflection",
    source = {
        url = "https://codeload.github.com/boostorg/describe/tar.gz/refs/tags/boost-1.92.0",
        sha256 = "4ef61ea2ca967b803e171f4756e03e201680d5dd19d014324f9a848e0d06863b",
        strip = 1,
    },
    dependencies = {
        "mp11",
      },
    header = {
        headers = {
            { src = "include/boost/describe.hpp", dst = "boost/describe.hpp" },
            { src = "include/boost/describe", dst = "boost/describe" },
          },
        include = "boost/describe.hpp",
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
