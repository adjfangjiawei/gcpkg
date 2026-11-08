-- libvorbis 1.3.7 -- ONE library, ONE build.lua + ONE features.yaml.
-- Verification: static registry/graph tests here; real builds for a
-- subset live in tests/extra.sh (GCPKG_EXTRA_DYNAMIC=1).
-- Vorbis codec on libogg.
-- Upstream is never patched: all adaptation is in this file.

local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "libvorbis",
    version = "1.3.7",
    license = "BSD-3-Clause",
    homepage = "https://xiph.org/vorbis/",
    description = "Vorbis audio codec on libogg",
    source = {
        url = "https://codeload.github.com/xiph/vorbis/tar.gz/refs/tags/v1.3.7",
        sha256 = "270c76933d0934e42c5ee0a54a36280e2d87af1de3cc3e584806357e237afd13",
        strip = 1,
    },
    dependencies = {
        "libogg",
      },
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
        "vorbis",
        "vorbisfile",
        "vorbisenc",
      },
      binaries = {},
    },
}
