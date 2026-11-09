-- inih r58 -- gcpkg port definition.
-- INI parser; only Meson build in the upstream tarball.

local recipe = require("gcpkg.recipe")

return recipe.meson {
    name = "inih",
    version = "r58",
    license = "BSD-3-Clause",
    homepage = "https://github.com/benhoyt/inih",
    description = "Simple .INI file parser",
    source = {
        url = "https://codeload.github.com/benhoyt/inih/tar.gz/refs/tags/r58",
        sha256 = "e79216260d5dffe809bda840be48ab0eec7737b2bb9f02d2275c1b46344ea7b7",
        strip = 1,
    },
    dependencies = {},
    meson = {
        options = {
          default_library = "static",
          with_INIReader = "true",
          distro_install = "true",
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
        "inih",
        "INIReader",
      },
      binaries = {},
    },
}
