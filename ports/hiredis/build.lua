-- hiredis 1.2.0 -- ONE library, ONE build.lua + ONE features.yaml.
-- Verification: static registry/graph tests here; real builds for a
-- subset live in tests/extra.sh (GCPKG_EXTRA_DYNAMIC=1).
-- Redis C client; tests/SSL disabled.
-- Upstream is never patched: all adaptation is in this file.

local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "hiredis",
    version = "1.2.0",
    license = "BSD-3-Clause",
    homepage = "https://github.com/redis/hiredis",
    description = "Minimalistic C client for Redis",
    source = {
        url = "https://codeload.github.com/redis/hiredis/tar.gz/refs/tags/v1.2.0",
        sha256 = "82ad632d31ee05da13b537c124f819eb88e18851d9cb0c30ae0552084811588c",
        strip = 1,
    },
    dependencies = {},
    cmake = {
        defines = {
          BUILD_TESTING = "OFF",
          DISABLE_TESTS = "ON",
          ENABLE_SSL = "OFF",
          BUILD_SHARED_LIBS = "OFF",
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
        "hiredis",
      },
      binaries = {},
    },
}
