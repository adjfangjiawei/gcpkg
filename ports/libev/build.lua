-- libev 4.33 -- gcpkg port definition.
-- libev event loop; ships a generated configure.

local recipe = require("gcpkg.recipe")
local fs = require("gcpkg.fs")

return recipe.autotools {
    name = "libev",
    version = "4.33",
    license = "BSD-2-Clause",
    homepage = "http://software.schmorp.de/pkg/libev.html",
    description = "High-performance event loop",
    source = {
        url = "https://dist.schmorp.de/libev/Attic/libev-4.33.tar.gz",
        sha256 = "507eb7b8d1015fbec5b935f34ebed15bf346bed04a11ab82b8eee848c4205aea",
        strip = 1,
    },
    dependencies = {},
    autotools = {
        args = {
          "--disable-shared",
          "--enable-static",
          "--disable-shared",
        },
    },
    pre_build = function(ctx)
        if not fs.isfile(ctx.src .. '/configure') then
            ctx.exec({ 'autoreconf', '-fi' }, { cwd = ctx.src, log = ctx.log })
        end
    end,
    exports = {
      includes = {
        "@PREFIX@/include",
      },
      libdirs = {
        "@LIBDIR@",
      },
      libs = {
        "ev",
      },
      binaries = {},
    },
}
