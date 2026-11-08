-- rapidjson 1.1.0 -- ONE library, ONE build.lua + ONE features.yaml.
-- Verification: static registry/graph tests here; real builds for a
-- subset live in tests/extra.sh (GCPKG_EXTRA_DYNAMIC=1).
-- Header-only C++ JSON library: no libraries exported, headers only.
-- Upstream is never patched: all adaptation is in this file.

local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "rapidjson",
    version = "1.1.0",
    license = "MIT",
    homepage = "https://rapidjson.org",
    description = "Header-only C++ JSON DOM/SAX parser",
    source = {
        url = "https://codeload.github.com/Tencent/rapidjson/tar.gz/refs/tags/v1.1.0",
        sha256 = "bf7ced29704a1e696fbccf2a2b4ea068e7774fa37f6d7dd4039d0787f8bed98e",
        strip = 1,
    },
    dependencies = {},
    cmake = {
        defines = {
          RAPIDJSON_BUILD_TESTS = "OFF",
          RAPIDJSON_BUILD_EXAMPLES = "OFF",
          RAPIDJSON_BUILD_DOC = "OFF",
          RAPIDJSON_BUILD_THIRDPARTY_GTEST = "OFF",
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
