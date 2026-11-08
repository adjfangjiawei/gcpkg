-- libsndfile 1.2.2 -- ONE library, ONE build.lua + ONE features.yaml.
-- Verification: static registry/graph tests here; real builds for a
-- subset live in tests/extra.sh (GCPKG_EXTRA_DYNAMIC=1).
-- Widest new chain: libogg + libvorbis + opus + flac -> libsndfile.
-- Upstream is never patched: all adaptation is in this file.

local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "libsndfile",
    version = "1.2.2",
    license = "LGPL-2.1",
    homepage = "https://github.com/libsndfile/libsndfile",
    description = "Audio file I/O on Ogg/Vorbis/Opus/FLAC",
    source = {
        url = "https://codeload.github.com/libsndfile/libsndfile/tar.gz/refs/tags/1.2.2",
        sha256 = "ffe12ef8add3eaca876f04087734e6e8e029350082f3251f565fa9da55b52121",
        strip = 1,
    },
    dependencies = {
        "libogg",
        "libvorbis",
        "opus",
        "flac",
      },
    cmake = {
        defines = {
          BUILD_TESTING = "OFF",
          BUILD_PROGRAMS = "OFF",
          BUILD_EXAMPLES = "OFF",
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
        "sndfile",
      },
      binaries = {},
    },
}
