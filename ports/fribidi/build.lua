-- fribidi 1.0.15 -- gcpkg port definition.
-- Unicode bidi algorithm; Meson only (no configure in tag).

local recipe = require("gcpkg.recipe")

return recipe.meson {
    name = "fribidi",
    version = "1.0.15",
    license = "LGPL-2.1",
    homepage = "https://github.com/fribidi/fribidi",
    description = "Unicode bidirectional algorithm",
    source = {
        url = "https://codeload.github.com/fribidi/fribidi/tar.gz/refs/tags/v1.0.15",
        sha256 = "0db5f0621b6fbfae5960c30da4f132009fd72bf4687f1b04a87a4cfc2a08ea38",
        strip = 1,
    },
    dependencies = {},
    meson = {
        options = {
          docs = "false",
          bin = "false",
          tests = "false",
          default_library = "static",
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
        "fribidi",
      },
      binaries = {},
    },
}
