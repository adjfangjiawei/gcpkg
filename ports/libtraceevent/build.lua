-- libtraceevent 1.8.4 -- ONE library, ONE build.lua + ONE features.yaml.
-- Verification: static registry/graph tests here; real builds for a
-- subset live in tests/linux-kernel.sh (GCPKG_KERNEL_DYNAMIC=1).
-- ftrace event parser; Meson docs disabled (upstream requires asciidoc).
-- Upstream is never patched: all adaptation is in this file.

local recipe = require("gcpkg.recipe")

return recipe.meson {
    name = "libtraceevent",
    version = "1.8.4",
    license = "LGPL-2.1",
    homepage = "https://git.kernel.org/pub/scm/libs/libtrace/libtraceevent.git",
    description = "Linux ftrace event parsing library",
    source = {
        url = "https://git.kernel.org/pub/scm/libs/libtrace/libtraceevent.git/snapshot/libtraceevent-1.8.4.tar.gz",
        sha256 = "dc456d4d2bf4b4cd4d0c737d3374a8093f9e5ca18c1d7fc2279a4bf41e613121",
        strip = 1,
    },
    dependencies = {},
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
        "traceevent",
      },
      binaries = {},
    },
}
