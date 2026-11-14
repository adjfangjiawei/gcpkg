-- libidn2 2.3.8 -- gcpkg port definition.
-- IDNA2008; depends on libunistring.

local recipe = require("gcpkg.recipe")
local fs = require("gcpkg.fs")

return recipe.autotools {
    name = "libidn2",
    version = "2.3.8",
    license = "LGPL-2.1",
    homepage = "https://www.gnu.org/software/libidn/",
    description = "GNU internationalized domain name library (IDNA2008)",
    source = {
        url = "https://ftp.gnu.org/gnu/libidn/libidn2-2.3.8.tar.gz",
        sha256 = "f557911bf6171621e1f72ff35f5b1825bb35b52ed45325dcdee931e5d3c0787a",
        strip = 1,
    },
    dependencies = {
        "libunistring",
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
        "idn2",
      },
      binaries = {},
    },
}
