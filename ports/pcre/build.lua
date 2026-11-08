-- pcre 8.45 -- ONE library, ONE build.lua + ONE features.yaml.
-- Verification: static registry/graph tests here; real builds for a
-- subset live in tests/extra.sh (GCPKG_EXTRA_DYNAMIC=1).
-- Legacy PCRE (complements the existing pcre2 port).
-- Upstream is never patched: all adaptation is in this file.

local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "pcre",
    version = "8.45",
    license = "BSD-3-Clause",
    homepage = "https://www.pcre.org",
    description = "Legacy Perl-compatible regex library",
    source = {
        url = "https://sourceforge.net/projects/pcre/files/pcre/8.45/pcre-8.45.tar.gz/download",
        sha256 = "4e6ce03e0336e8b4a3d6c2b70b1c5e18590a5673a98186da90d4f33c23defc09",
        strip = 1,
    },
    dependencies = {},
    cmake = {
        defines = {
          PCRE_BUILD_TESTS = "OFF",
          PCRE_BUILD_PCREGREP = "OFF",
          PCRE_BUILD_PCRECPP = "OFF",
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
        "pcre",
      },
      binaries = {},
    },
}
