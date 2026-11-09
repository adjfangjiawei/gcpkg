-- byte-lite v0.3.0 -- gcpkg port definition.
-- std::byte backport for pre-C++17 compilers.

local recipe = require("gcpkg.recipe")

return recipe.header {
    name = "byte-lite",
    version = "v0.3.0",
    license = "BSL-1.0",
    homepage = "https://github.com/martinmoene/byte-lite",
    description = "C++17 std::byte backport",
    source = {
        url = "https://codeload.github.com/martinmoene/byte-lite/tar.gz/refs/tags/v0.3.0",
        sha256 = "1a19e237b12bb098297232b0a74ec08c18ac07ac5ac6e659c1d5d8a4ed0e4813",
        strip = 1,
    },
    dependencies = {},
    header = {
        headers = {
            { src = "include/nonstd/byte.hpp", dst = "nonstd/byte.hpp" },
          },
        include = "nonstd/byte.hpp",
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
