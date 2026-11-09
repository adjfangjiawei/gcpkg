-- XCB protocol descriptions + xcbgen Python module (data-only port)
-- gcpkg port definition.
local recipe = require("gcpkg.recipe")

return recipe.autotools {
    name = "xcb-proto",
    version = "1.17.0",
    description = "XCB protocol descriptions + xcbgen Python module (data-only port)",
    license = "MIT",
    homepage = "https://gitlab.freedesktop.org/xorg/proto/xcb-proto",
    source = {
        url = "https://www.x.org/archive/individual/proto/xcb-proto-1.17.0.tar.xz",
        sha256 = "2c1bacd2110f4799f74de6ebb714b94cf6f80fb112316b1219480fd22562148c",
        strip = 1,
    },
    dependencies = {},
    autotools = {
        args = {},
    },
    exports = {
      includes = { "@PREFIX@/include" }
    },
}
