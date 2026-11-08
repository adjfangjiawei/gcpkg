-- simdjson 3.10.0 -- ONE library, ONE build.lua + ONE features.yaml.
-- Verification: static registry/graph tests here; real builds for a
-- subset live in tests/extra.sh (GCPKG_EXTRA_DYNAMIC=1).
-- SIMD JSON parser; developer/test targets disabled.
-- Upstream is never patched: all adaptation is in this file.

local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "simdjson",
    version = "3.10.0",
    license = "Apache-2.0",
    homepage = "https://github.com/simdjson/simdjson",
    description = "SIMD JSON parser for C++",
    source = {
        url = "https://codeload.github.com/simdjson/simdjson/tar.gz/refs/tags/v3.10.0",
        sha256 = "9c30552f1dd0ee3d0832bb1c6b7b97d813b18d5ef294c10dcb6fc242e5947de8",
        strip = 1,
    },
    dependencies = {},
    cmake = {
        defines = {
          BUILD_TESTING = "OFF",
          SIMDJSON_DEVELOPER_MODE = "OFF",
          SIMDJSON_JUST_LIBRARY = "ON",
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
      libs = {
        "simdjson",
      },
      binaries = {},
    },
}
