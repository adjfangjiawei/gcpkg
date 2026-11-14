-- mpc 1.3.1 -- gcpkg port definition.
-- Needs gmp + mpfr; classic GCC numeric stack.

local recipe = require("gcpkg.recipe")
local fs = require("gcpkg.fs")

return recipe.autotools {
    name = "mpc",
    version = "1.3.1",
    license = "LGPL-3.0",
    homepage = "https://www.multiprecision.org/mpc/",
    description = "GNU MPC complex arithmetic library",
    source = {
        url = "https://ftp.gnu.org/gnu/mpc/mpc-1.3.1.tar.gz",
        sha256 = "ab642492f5cf882b74aa0cb730cd410a81edcdbec895183ce930e706c1c759b8",
        strip = 1,
    },
    dependencies = {
        "gmp",
        "mpfr",
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
        "mpc",
      },
      binaries = {},
    },
}
