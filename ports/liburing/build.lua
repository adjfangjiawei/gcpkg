-- Linux io_uring helper library
-- ONE library, ONE build.lua and ONE features.yaml. Upstream sources
-- are downloaded verbatim (sha256 verified) and never patched.
local recipe = require("gcpkg.recipe")

return recipe.make {
    name = "liburing",
    version = "2.9",
    description = "Linux io_uring helper library",
    license = "MIT",
    homepage = "https://github.com/axboe/liburing",
    source = {
        url = "https://github.com/axboe/liburing/archive/refs/tags/liburing-2.9.tar.gz",
        sha256 = "897b1153b55543e8b92a5a3eb9b906537a5fedcf8afaf241f8b8787940c79f8d",
        strip = 1,
    },
    dependencies = {},
    make = {
        targets = { "library" },
        install_target = "install",
    },
    pre_build = function(ctx)
        ctx.exec({ './configure', '--prefix=' .. ctx.prefix, '--libdir=' .. ctx.prefix .. '/lib', '--includedir=' .. ctx.prefix .. '/include' }, { cwd = ctx.src, log = ctx.log })
    end,
    exports = {
      includes = { "@PREFIX@/include" },
      libdirs = { "@LIBDIR@" },
      libs = { "uring" }
    },
}
