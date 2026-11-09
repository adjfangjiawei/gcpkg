-- gmp 6.3.0 -- gcpkg port definition.
-- GNU MP; L0 foundation of the numeric/crypto chain.

local recipe = require("gcpkg.recipe")
local fs = require("gcpkg.fs")

return recipe.autotools {
    name = "gmp",
    version = "6.3.0",
    license = "LGPL-3.0/GPL-2.0",
    homepage = "https://gmplib.org",
    description = "GNU multiple precision arithmetic library",
    source = {
        url = "https://gmplib.org/download/gmp/gmp-6.3.0.tar.xz",
        sha256 = "a3c2b80201b89e68616f4ad30bc66aee4927c3ce50e33929ca819d5c43538898",
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
        "gmp",
      },
      binaries = {},
    },
}
