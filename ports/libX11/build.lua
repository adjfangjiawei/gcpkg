-- Xlib: core X11 client library
-- ONE library, ONE build.lua and ONE features.yaml. Upstream sources
-- are downloaded verbatim (sha256 verified) and never patched.
local recipe = require("gcpkg.recipe")

return recipe.autotools {
    name = "libX11",
    version = "1.8.12",
    description = "Xlib: core X11 client library",
    license = "MIT",
    homepage = "https://gitlab.freedesktop.org/xorg/lib/libX11",
    source = {
        url = "https://www.x.org/archive/individual/lib/libX11-1.8.12.tar.xz",
        sha256 = "fa026f9bb0124f4d6c808f9aef4057aad65e7b35d8ff43951cef0abe06bb9a9a",
        strip = 1,
    },
    dependencies = { "xorgproto", "libxcb" },
    autotools = {
        args = { "--disable-shared", "--disable-specs" },
    },
    exports = {
      includes = { "@PREFIX@/include" },
      libdirs = { "@LIBDIR@" },
      libs = { "X11" }
    },
}
