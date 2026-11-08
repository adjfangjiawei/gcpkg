-- libmaxminddb 1.12.2 -- ONE library, ONE build.lua + ONE features.yaml.
-- Verification: static registry/graph tests here; real builds for a
-- subset live in tests/extra.sh (GCPKG_EXTRA_DYNAMIC=1).
-- MaxMind DB / GeoIP reader.
-- Upstream is never patched: all adaptation is in this file.

local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "libmaxminddb",
    version = "1.12.2",
    license = "Apache-2.0",
    homepage = "https://github.com/maxmind/libmaxminddb",
    description = "MaxMind DB (GeoIP) reader",
    source = {
        url = "https://codeload.github.com/maxmind/libmaxminddb/tar.gz/refs/tags/1.12.2",
        sha256 = "c325cb952d512b12a715e0a08aedff0d16791db528dc3f23af576057398d66ab",
        strip = 1,
    },
    dependencies = {},
    cmake = {
        defines = {
          BUILD_TESTING = "OFF",
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
        "maxminddb",
      },
      binaries = {},
    },
}
