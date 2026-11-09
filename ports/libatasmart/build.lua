-- libatasmart 0.19 -- gcpkg port definition.
-- ATA SMART disk health library; ships ./configure.

local recipe = require("gcpkg.recipe")
local fs = require("gcpkg.fs")

return recipe.autotools {
    name = "libatasmart",
    version = "0.19",
    license = "LGPL-2.1",
    homepage = "https://0pointer.de/blog/projects.html",
    description = "ATA SMART disk health library",
    source = {
        url = "https://0pointer.de/public/libatasmart-0.19.tar.xz",
        sha256 = "61f0ea345f63d28ab2ff0dc352c22271661b66bf09642db3a4049ac9dbdb0f8d",
        strip = 1,
    },
    dependencies = {},
    autotools = {
        args = {
          "--disable-shared",
          "--enable-static",
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
        "atasmart",
      },
      binaries = {},
    },
}
