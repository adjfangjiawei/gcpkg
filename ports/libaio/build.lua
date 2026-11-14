-- Linux native asynchronous I/O library
-- gcpkg port definition.
local recipe = require("gcpkg.recipe")

return recipe.make {
    name = "libaio",
    version = "0.3.113",
    description = "Linux native asynchronous I/O library",
    license = "LGPL-2.1",
    homepage = "https://pagure.io/libaio",
    source = {
        url = "https://deb.debian.org/debian/pool/main/liba/libaio/libaio_0.3.113.orig.tar.gz",
        sha256 = "2c44d1c5fd0d43752287c9ae1eb9c023f04ef848ea8d4aafa46e9aedb678200b",
        strip = 1,
    },
    dependencies = {},
    make = {
        vars = function(ctx) return {
              prefix = ctx.prefix
            } end,
        install_target = "install",
    },
    exports = {
      includes = { "@PREFIX@/include" },
      libdirs = { "@LIBDIR@" },
      libs = { "aio" }
    },
}
