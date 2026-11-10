-- harfbuzz 15.1.0 -- gcpkg port definition.
-- Text shaping engine; static Meson build on source-built freetype + glib, no system utilities.

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
          default_library = "static",
          tests = "disabled",
          docs = "disabled",
          doc_tests = "false",
          utilities = "disabled",
          introspection = "disabled",
          benchmark = "disabled",
          cairo = "disabled",
          chafa = "disabled",
          gobject = "disabled",
          icu = "disabled",
          png = "disabled",
          zlib = "disabled",
          freetype = "enabled",
          glib = "enabled",
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
