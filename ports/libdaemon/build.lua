-- libdaemon 0.14 -- gcpkg port definition.
-- Unix daemon helper; ships ./configure.

local recipe = require("gcpkg.recipe")
local fs = require("gcpkg.fs")

return recipe.autotools {
    name = "libdaemon",
    version = "0.14",
    license = "LGPL-2.1",
    homepage = "https://0pointer.de/lennart/projects/libdaemon/",
    description = "Unix daemon helper library",
    source = {
        url = "https://0pointer.de/lennart/projects/libdaemon/libdaemon-0.14.tar.gz",
        sha256 = "fd23eb5f6f986dcc7e708307355ba3289abe03cc381fc47a80bca4a50aa6b834",
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
        "daemon",
      },
      binaries = {},
    },
}
