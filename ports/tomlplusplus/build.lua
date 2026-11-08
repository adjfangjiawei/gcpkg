-- tomlplusplus 3.4.0 -- ONE library, ONE build.lua + ONE features.yaml.
-- Verification: static registry/graph tests in tests/r10.sh; real
-- builds in GCPKG_R10_DYNAMIC=1 ./tests/r10.sh.
-- Header-only TOML library: no libraries exported.
-- Upstream is never patched: all adaptation is in this file.

local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "tomlplusplus",
    version = "3.4.0",
    license = "MIT",
    homepage = "https://github.com/marzer/tomlplusplus",
    description = "Header-only TOML parser/serializer for C++17",
    source = {
        url = "https://codeload.github.com/marzer/tomlplusplus/tar.gz/refs/tags/v3.4.0",
        sha256 = "8517f65938a4faae9ccf8ebb36631a38c1cadfb5efa85d9a72e15b9e97d25155",
        strip = 1,
    },
    dependencies = {},
    cmake = {
        defines = {
          BUILD_TESTING = "OFF",
          tomlplusplus_BUILD_EXAMPLES = "OFF",
          tomlplusplus_BUILD_TESTS = "OFF",
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
