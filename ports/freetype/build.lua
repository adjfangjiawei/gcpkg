-- freetype 2.13.3 -- ONE library, ONE build.lua + ONE features.yaml.
-- Verification: static registry/graph tests here; real builds for a
-- subset live in tests/linux-base.sh (GCPKG_BASE_DYNAMIC=1).
-- Font renderer on zlib, bzip2, libpng and brotli (all existing ports).
-- Upstream is never patched: all adaptation is in this file.

local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "freetype",
    version = "2.13.3",
    license = "FTL/GPL-2.0",
    homepage = "https://freetype.org",
    description = "FreeType font rendering engine",
    source = {
        url = "https://download.savannah.gnu.org/releases/freetype/freetype-2.13.3.tar.xz",
        sha256 = "0550350666d427c74daeb85d5ac7bb353acba5f76956395995311a9c6f063289",
        strip = 1,
    },
    dependencies = {
        "zlib",
        "bzip2",
        "libpng",
        "brotli",
      },
    cmake = {
        defines = {
          BUILD_TESTING = "OFF",
          FT_DISABLE_ZLIB = "OFF",
        },
        args = {},
    },
    exports = {
      includes = {
        "@PREFIX@/include",
        "@PREFIX@/include/freetype2",
      },
      libdirs = {
        "@LIBDIR@",
      },
      libs = {
        "freetype",
      },
      binaries = {},
    },
}
