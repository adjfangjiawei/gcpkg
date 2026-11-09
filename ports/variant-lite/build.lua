-- variant-lite v2.0.0 -- gcpkg port definition.
-- std::variant backport for pre-C++17 compilers.

local recipe = require("gcpkg.recipe")

return recipe.header {
    name = "variant-lite",
    version = "v2.0.0",
    license = "BSL-1.0",
    homepage = "https://github.com/martinmoene/variant-lite",
    description = "C++17 std::variant backport",
    source = {
        url = "https://codeload.github.com/martinmoene/variant-lite/tar.gz/refs/tags/v2.0.0",
        sha256 = "70c1509e24d03abfd22d2e702ab398238e69658b7b2890ce1d7e9731d6b5a7cb",
        strip = 1,
    },
    dependencies = {},
    header = {
        headers = {
            { src = "include/nonstd/variant.hpp", dst = "nonstd/variant.hpp" },
          },
        include = "nonstd/variant.hpp",
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
