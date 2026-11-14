-- X C Binding (XCB) library
-- gcpkg port definition.
local recipe = require("gcpkg.recipe")

return recipe.autotools {
    name = "libxcb",
    version = "1.17.0",
    description = "X C Binding (XCB) library",
    license = "MIT",
    homepage = "https://xcb.freedesktop.org",
    source = {
        url = "https://www.x.org/archive/individual/lib/libxcb-1.17.0.tar.xz",
        sha256 = "599ebf9996710fea71622e6e184f3a8ad5b43d0e5fa8c4e407123c88a59a6d55",
        strip = 1,
    },
    dependencies = { "xorgproto", "xcb-proto", "libXau", "libXdmcp" },
    autotools = {
        args = { "--disable-docs" },
    },
    exports = {
      includes = { "@PREFIX@/include" },
      libdirs = { "@LIBDIR@" },
      libs = { "xcb" }
    },
}
