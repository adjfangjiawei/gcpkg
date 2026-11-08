-- jsoncpp 1.9.6 -- ONE library, ONE build.lua + ONE features.yaml.
-- Verification: static registry/graph tests in tests/r10.sh; real
-- builds in GCPKG_R10_DYNAMIC=1 ./tests/r10.sh.
-- C++ JSON reader/writer; static lib + tests off.
-- Upstream is never patched: all adaptation is in this file.

local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "jsoncpp",
    version = "1.9.6",
    license = "MIT",
    homepage = "https://github.com/open-source-parsers/jsoncpp",
    description = "C++ JSON reader/writer",
    source = {
        url = "https://codeload.github.com/open-source-parsers/jsoncpp/tar.gz/refs/tags/1.9.6",
        sha256 = "f93b6dd7ce796b13d02c108bc9f79812245a82e577581c4c9aabe57075c90ea2",
        strip = 1,
    },
    dependencies = {},
    cmake = {
        defines = {
          BUILD_TESTING = "OFF",
          JSONCPP_WITH_TESTS = "OFF",
          JSONCPP_WITH_POST_BUILD_UNITTEST = "OFF",
          JSONCPP_WITH_EXAMPLE = "OFF",
          BUILD_SHARED_LIBS = "OFF",
          BUILD_STATIC_LIBS = "ON",
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
        "jsoncpp",
      },
      binaries = {},
    },
}
