-- libunistring 1.3 -- gcpkg port definition.
-- Unicode primitives for libidn2 and GnuTLS.

local recipe = require("gcpkg.recipe")
local fs = require("gcpkg.fs")

return recipe.autotools {
    name = "libunistring",
    version = "1.3",
    license = "GPL-3.0/LGPL-3.0",
    homepage = "https://www.gnu.org/software/libunistring/",
    description = "GNU Unicode string library",
    source = {
        url = "https://ftp.gnu.org/gnu/libunistring/libunistring-1.3.tar.xz",
        sha256 = "f245786c831d25150f3dfb4317cda1acc5e3f79a5da4ad073ddca58886569527",
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
        "unistring",
      },
      binaries = {},
    },
}
