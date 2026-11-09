-- smartmontools 7.4 -- gcpkg port definition.
-- SMART disk health query tools; ships ./configure.

local recipe = require("gcpkg.recipe")
local fs = require("gcpkg.fs")

return recipe.autotools {
    name = "smartmontools",
    version = "7.4",
    license = "GPL-2.0",
    homepage = "https://www.smartmontools.org",
    description = "SMART disk health query tools",
    source = {
        url = "https://downloads.sourceforge.net/project/smartmontools/smartmontools/7.4/smartmontools-7.4.tar.gz",
        sha256 = "e9a61f641ff96ca95319edfb17948cd297d0cd3342736b2c49c99d4716fb993d",
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
      libs = {},
      binaries = {},
    },
}
