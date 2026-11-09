-- Low-level pixel manipulation library (Cairo/X.org)
-- gcpkg port definition.
local recipe = require("gcpkg.recipe")

return recipe.meson {
    name = "pixman",
    version = "0.44.2",
    description = "Low-level pixel manipulation library (Cairo/X.org)",
    license = "MIT",
    homepage = "https://cairographics.org",
    source = {
        url = "https://cairographics.org/releases/pixman-0.44.2.tar.gz",
        sha256 = "6349061ce1a338ab6952b92194d1b0377472244208d47ff25bef86fc71973466",
        strip = 1,
    },
    dependencies = {},
    meson = {
        options = {
          tests = "disabled",
          demos = "disabled",
          gtk = "disabled",
          libpng = "disabled",
          openmp = "disabled"
        },
        auto_features = "disabled",
    },
    exports = {
      includes = { "@PREFIX@/include/pixman-1", "@PREFIX@/include" },
      libdirs = { "@LIBDIR@" },
      libs = { "pixman-1" }
    },
}
