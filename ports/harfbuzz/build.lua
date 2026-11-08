-- harfbuzz 15.1.0 -- ONE library, ONE build.lua + ONE features.yaml.
-- Verification: static registry/graph tests here; real builds for a
-- subset live in tests/linux-base.sh (GCPKG_BASE_DYNAMIC=1).
-- Text shaping engine; Meson, depends on freetype + glib.
-- Upstream is never patched: all adaptation is in this file.

local recipe = require("gcpkg.recipe")

return recipe.meson {
    name = "harfbuzz",
    version = "15.1.0",
    license = "MIT",
    homepage = "https://harfbuzz.github.io",
    description = "OpenType text shaping engine",
    source = {
        url = "https://codeload.github.com/harfbuzz/harfbuzz/tar.gz/refs/tags/15.1.0",
        sha256 = "5c057929413b8664592fea67edea5c2c47b4ffb0bf5f4accb5164bc6acc69d94",
        strip = 1,
    },
    dependencies = {
        "freetype",
        "glib",
      },
    meson = {
        options = {
          tests = "disabled",
          docs = "disabled",
        },
        args = {},
    },
    exports = {
      includes = {
        "@PREFIX@/include",
        "@PREFIX@/include/harfbuzz",
      },
      libdirs = {
        "@LIBDIR@",
      },
      libs = {
        "harfbuzz",
      },
      binaries = {},
    },
}
