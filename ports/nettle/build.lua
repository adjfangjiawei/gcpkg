-- nettle 3.10 -- gcpkg port definition.
-- Low-level crypto built on gmp.

local recipe = require("gcpkg.recipe")
local fs = require("gcpkg.fs")

return recipe.autotools {
    name = "nettle",
    version = "3.10",
    license = "LGPL-2.1",
    homepage = "https://www.lysator.liu.se/~nisse/nettle/",
    description = "Nettle low-level cryptographic library",
    source = {
        url = "https://ftp.gnu.org/gnu/nettle/nettle-3.10.tar.gz",
        sha256 = "b4c518adb174e484cb4acea54118f02380c7133771e7e9beb98a0787194ee47c",
        strip = 1,
    },
    dependencies = {
        "gmp",
      },
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
        -- Static libbrotlidec needs libbrotlicommon; pkg-config does not add it.
        if ctx.name == "fontconfig" then
            ctx.env.LIBS = "-lbrotlicommon " .. (ctx.env.LIBS or "")
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
        "nettle",
        "hogweed",
      },
      binaries = {},
    },
}
