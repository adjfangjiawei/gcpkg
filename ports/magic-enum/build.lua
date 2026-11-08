-- magic-enum 0.9.7 -- ONE library, ONE build.lua + ONE features.yaml.
-- Verification: static registry/graph tests in tests/r10.sh; real
-- builds in GCPKG_R10_DYNAMIC=1 ./tests/r10.sh.
-- Header-only C++ enum reflection: headers only.
-- Upstream is never patched: all adaptation is in this file.

local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "magic-enum",
    version = "0.9.7",
    license = "MIT",
    homepage = "https://github.com/Neargye/magic_enum",
    description = "Header-only C++17 enum reflection",
    source = {
        url = "https://codeload.github.com/Neargye/magic_enum/tar.gz/refs/tags/v0.9.7",
        sha256 = "b403d3dad4ef542fdc3024fa37d3a6cedb4ad33c72e31b6d9bab89dcaf69edf7",
        strip = 1,
    },
    dependencies = {},
    cmake = {
        defines = {
          BUILD_TESTING = "OFF",
          MAGIC_ENUM_OPT_BUILD_EXAMPLES = "OFF",
          MAGIC_ENUM_OPT_BUILD_TESTS = "OFF",
        },
        args = {},
    },
    exports = {
      includes = {
        "@PREFIX@/include",
      },
      libdirs = {
        "@LIBDIR@",
      },
      libs = {},
      binaries = {},
    },
}
