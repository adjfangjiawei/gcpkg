-- flac 1.4.3 -- ONE library, ONE build.lua + ONE features.yaml.
-- Verification: static registry/graph tests here; real builds for a
-- subset live in tests/extra.sh (GCPKG_EXTRA_DYNAMIC=1).
-- FLAC codec on libogg.
-- Upstream is never patched: all adaptation is in this file.

local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "flac",
    version = "1.4.3",
    license = "BSD-3-Clause",
    homepage = "https://xiph.org/flac/",
    description = "Free Lossless Audio Codec on libogg",
    source = {
        url = "https://codeload.github.com/xiph/flac/tar.gz/refs/tags/1.4.3",
        sha256 = "0a4bb82a30609b606650d538a804a7b40205366ce8fc98871b0ecf3fbb0611ee",
        strip = 1,
    },
    dependencies = {
        "libogg",
      },
    cmake = {
        defines = {
          BUILD_TESTING = "OFF",
          BUILD_SHARED_LIBS = "OFF",
          BUILD_PROGRAMS = "OFF",
          BUILD_EXAMPLES = "OFF",
          INSTALL_MANPAGES = "OFF",
          WITH_OGG = "ON",
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
        "FLAC",
      },
      binaries = {},
    },
}
