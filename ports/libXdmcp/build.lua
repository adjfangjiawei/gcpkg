-- X Display Manager Control Protocol library
-- ONE library, ONE build.lua and ONE features.yaml. Upstream sources
-- are downloaded verbatim (sha256 verified) and never patched.
local recipe = require("gcpkg.recipe")

return recipe.autotools {
    name = "libXdmcp",
    version = "1.1.5",
    description = "X Display Manager Control Protocol library",
    license = "MIT",
    homepage = "https://gitlab.freedesktop.org/xorg/lib/libXdmcp",
    source = {
        url = "https://www.x.org/archive/individual/lib/libXdmcp-1.1.5.tar.xz",
        sha256 = "d8a5222828c3adab70adf69a5583f1d32eb5ece04304f7f8392b6a353aa2228c",
        strip = 1,
    },
    dependencies = { "xorgproto" },
    autotools = {
        args = { "--disable-shared" },
    },
    exports = {
      includes = { "@PREFIX@/include" },
      libdirs = { "@LIBDIR@" },
      libs = { "Xdmcp" }
    },
}
