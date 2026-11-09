-- optional-lite v3.6.0 -- gcpkg port definition.
-- std::optional backport for pre-C++17 compilers.

local recipe = require("gcpkg.recipe")

return recipe.header {
    name = "optional-lite",
    version = "v3.6.0",
    license = "BSL-1.0",
    homepage = "https://github.com/martinmoene/optional-lite",
    description = "C++17 std::optional backport",
    source = {
        url = "https://codeload.github.com/martinmoene/optional-lite/tar.gz/refs/tags/v3.6.0",
        sha256 = "2be17fcfc764809612282c3e728cabc42afe703b9dc333cc87c48d882fcfc2c2",
        strip = 1,
    },
    dependencies = {},
    header = {
        headers = {
            { src = "include/nonstd/optional.hpp", dst = "nonstd/optional.hpp" },
          },
        include = "nonstd/optional.hpp",
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
