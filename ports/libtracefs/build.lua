-- libtracefs 1.8.2 -- gcpkg port definition.
-- tracefs wrapper; Meson, depends on libtraceevent, docs disabled.

local recipe = require("gcpkg.recipe")

return recipe.meson {
    name = "libtracefs",
    version = "1.8.2",
    license = "LGPL-2.1",
    homepage = "https://git.kernel.org/pub/scm/libs/libtrace/libtracefs.git",
    description = "tracefs filesystem wrapper (kernel tracing)",
    source = {
        url = "https://git.kernel.org/pub/scm/libs/libtrace/libtracefs.git/snapshot/libtracefs-1.8.2.tar.gz",
        sha256 = "255980e1da5648fbbc32777ed8457b485b2b96f3449674610b46d9c437271209",
        strip = 1,
    },
    dependencies = {
        "libtraceevent",
      },
    meson = {
        options = {
          doc = "false",
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
        "tracefs",
      },
      binaries = {},
    },
}
