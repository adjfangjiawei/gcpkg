-- expected-lite v0.8.0 -- gcpkg port definition.
-- std::expected backport for pre-C++23 compilers.

local recipe = require("gcpkg.recipe")

return recipe.header {
    name = "expected-lite",
    version = "v0.8.0",
    license = "BSL-1.0",
    homepage = "https://github.com/martinmoene/expected-lite",
    description = "C++23 std::expected backport",
    source = {
        url = "https://codeload.github.com/martinmoene/expected-lite/tar.gz/refs/tags/v0.8.0",
        sha256 = "27649f30bd9d4fe7b193ab3eb6f78c64d0f585c24c085f340b4722b3d0b5e701",
        strip = 1,
    },
    dependencies = {},
    header = {
        headers = {
            { src = "include/nonstd/expected.hpp", dst = "nonstd/expected.hpp" },
          },
        include = "nonstd/expected.hpp",
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
