-- nlohmann-json 3.11.3 -- ONE library, ONE build.lua + ONE features.yaml.
-- Verification: static registry/graph tests in tests/r10.sh; real
-- builds in GCPKG_R10_DYNAMIC=1 ./tests/r10.sh.
-- Header-only JSON for Modern C++: headers only.
-- Upstream is never patched: all adaptation is in this file.

local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "nlohmann-json",
    version = "3.11.3",
    license = "MIT",
    homepage = "https://github.com/nlohmann/json",
    description = "Header-only JSON for Modern C++",
    source = {
        url = "https://codeload.github.com/nlohmann/json/tar.gz/refs/tags/v3.11.3",
        sha256 = "0d8ef5af7f9794e3263480193c491549b2ba6cc74bb018906202ada498a79406",
        strip = 1,
    },
    dependencies = {},
    cmake = {
        defines = {
          BUILD_TESTING = "OFF",
          JSON_BuildTests = "OFF",
          JSON_MultipleHeaders = "ON",
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
