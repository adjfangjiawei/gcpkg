-- span-lite v0.11.0 -- gcpkg port definition.
-- std::span backport; upstream CMake install rules are not needed.

local recipe = require("gcpkg.recipe")

return recipe.header {
    name = "span-lite",
    version = "v0.11.0",
    license = "BSL-1.0",
    homepage = "https://github.com/martinmoene/span-lite",
    description = "C++20 std::span backport for C++11/14/17",
    source = {
        url = "https://codeload.github.com/martinmoene/span-lite/tar.gz/refs/tags/v0.11.0",
        sha256 = "ef4e028e18ff21044da4b4641ca1bc8a2e2d656e2028322876c0e1b9b6904f9d",
        strip = 1,
    },
    dependencies = {},
    header = {
        headers = {
            { src = "include/nonstd/span.hpp", dst = "nonstd/span.hpp" },
          },
        include = "nonstd/span.hpp",
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
