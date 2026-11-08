-- miniz 3.0.2 -- ONE library, ONE build.lua + ONE features.yaml.
-- Verification: static registry/graph tests here; real builds for a
-- subset live in tests/extra.sh (GCPKG_EXTRA_DYNAMIC=1).
-- Single-file zlib/zip replacement.
-- Upstream is never patched: all adaptation is in this file.

local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "miniz",
    version = "3.0.2",
    license = "MIT",
    homepage = "https://github.com/richgel999/miniz",
    description = "Single-file zlib/zip replacement",
    source = {
        url = "https://codeload.github.com/richgel999/miniz/tar.gz/refs/tags/3.0.2",
        sha256 = "c4b4c25a4eb81883448ff8924e6dba95c800094a198dc9ce66a292ac2ef8e018",
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
        "miniz",
      },
      binaries = {},
    },
}
