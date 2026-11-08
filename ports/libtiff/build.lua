-- libtiff 4.7.0 -- ONE library, ONE build.lua + ONE features.yaml.
-- Verification: static registry/graph tests here; real builds for a
-- subset live in tests/linux-base.sh (GCPKG_BASE_DYNAMIC=1).
-- TIFF on zlib + xz + zstd + libjpeg-turbo (existing and new ports).
-- Upstream is never patched: all adaptation is in this file.

local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "libtiff",
    version = "4.7.0",
    license = "libtiff",
    homepage = "https://libtiff.gitlab.io/libtiff/",
    description = "TIFF image format library",
    source = {
        url = "https://download.osgeo.org/libtiff/tiff-4.7.0.tar.gz",
        sha256 = "67160e3457365ab96c5b3286a0903aa6e78bdc44c4bc737d2e486bcecb6ba976",
        strip = 1,
    },
    dependencies = {
        "zlib",
        "xz",
        "zstd",
        "libjpeg-turbo",
      },
    cmake = {
        defines = {
          BUILD_TESTING = "OFF",
          tests = "OFF",
          tools = "OFF",
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
        "tiff",
      },
      binaries = {},
    },
}
