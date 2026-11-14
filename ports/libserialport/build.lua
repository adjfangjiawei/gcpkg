-- libserialport 0.1.2 -- gcpkg port definition.
-- sigrok serial-port library; tag archive needs autoreconf.

local recipe = require("gcpkg.recipe")
local fs = require("gcpkg.fs")

return recipe.autotools {
    name = "libserialport",
    version = "0.1.2",
    license = "LGPL-3.0",
    homepage = "https://sigrok.org/wiki/Libserialport",
    description = "Serial port access library (sigrok)",
    source = {
        url = "https://sigrok.org/download/source/libserialport/libserialport-0.1.2.tar.gz",
        sha256 = "5deb92b5ca72c0347b07b786848350deca2dcfd975ce613b8e0e1d947a4b4ca9",
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
        "serialport",
      },
      binaries = {},
    },
}
