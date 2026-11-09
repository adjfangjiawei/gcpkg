-- libmodbus 3.1.11 -- gcpkg port definition.
-- Modbus library; GitHub tag needs autoreconf first.

local recipe = require("gcpkg.recipe")
local fs = require("gcpkg.fs")

return recipe.autotools {
    name = "libmodbus",
    version = "3.1.11",
    license = "LGPL-2.1",
    homepage = "https://libmodbus.org",
    description = "Modbus protocol library",
    source = {
        url = "https://codeload.github.com/stephane/libmodbus/tar.gz/refs/tags/v3.1.11",
        sha256 = "8a750452ef86a53de6cec6fbca67bd5be08d0a1e87278a422fbce3003fd42d99",
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
        "modbus",
      },
      binaries = {},
    },
}
