-- JSON implementation in C
-- ONE library, ONE build.lua and ONE features.yaml. Upstream sources
-- are downloaded verbatim (sha256 verified) and never patched.
local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "json-c",
    version = "0.18",
    description = "JSON implementation in C",
    license = "MIT",
    homepage = "https://github.com/json-c/json-c",
    source = {
        url = "https://github.com/json-c/json-c/archive/refs/tags/json-c-0.18-20240915.tar.gz",
        sha256 = "3112c1f25d39eca661fe3fc663431e130cc6e2f900c081738317fba49d29e298",
        strip = 1,
    },
    dependencies = {},
    cmake = {
        defines = {
          BUILD_SHARED_LIBS = "OFF",
          DISABLE_WERROR = "ON",
          ENABLE_TESTING = "OFF"
        },
    },
    exports = {
      includes = { "@PREFIX@/include/json-c", "@PREFIX@/include" },
      libdirs = { "@LIBDIR@" },
      libs = { "json-c" }
    },
}
