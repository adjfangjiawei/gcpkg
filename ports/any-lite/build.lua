-- any-lite v0.4.0 -- gcpkg port definition.
-- std::any backport for pre-C++17 compilers.

local recipe = require("gcpkg.recipe")

return recipe.header {
    name = "any-lite",
    version = "v0.4.0",
    license = "BSL-1.0",
    homepage = "https://github.com/martinmoene/any-lite",
    description = "C++17 std::any backport",
    source = {
        url = "https://codeload.github.com/martinmoene/any-lite/tar.gz/refs/tags/v0.4.0",
        sha256 = "889549098291a1313d2fc8cd12dcdab13214d05cdce7ed5fe2dc724cdd7b3125",
        strip = 1,
    },
    dependencies = {},
    header = {
        headers = {
            { src = "include/nonstd/any.hpp", dst = "nonstd/any.hpp" },
          },
        include = "nonstd/any.hpp",
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
