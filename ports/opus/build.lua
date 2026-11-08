-- opus 1.5.2 -- ONE library, ONE build.lua + ONE features.yaml.
-- Verification: static registry/graph tests here; real builds for a
-- subset live in tests/extra.sh (GCPKG_EXTRA_DYNAMIC=1).
-- Opus audio codec; CMake build (tarball also has autotools/meson).
-- Upstream is never patched: all adaptation is in this file.

local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "opus",
    version = "1.5.2",
    license = "BSD-3-Clause",
    homepage = "https://opus-codec.org",
    description = "Opus audio codec",
    source = {
        url = "https://codeload.github.com/xiph/opus/tar.gz/refs/tags/v1.5.2",
        sha256 = "9480e329e989f70d69886ded470c7f8cfe6c0667cc4196d4837ac9e668fb7404",
        strip = 1,
    },
    dependencies = {},
    cmake = {
        defines = {
          BUILD_TESTING = "OFF",
          OPUS_BUILD_TESTING = "OFF",
          OPUS_BUILD_PROGRAMS = "OFF",
          OPUS_BUILD_SHARED_LIBRARY = "OFF",
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
        "opus",
      },
      binaries = {},
    },
}
