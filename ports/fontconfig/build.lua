-- fontconfig 2.16.0 -- gcpkg port definition.
-- Font configuration on freetype + expat.

local recipe = require("gcpkg.recipe")
local fs = require("gcpkg.fs")

return recipe.autotools {
    name = "fontconfig",
    version = "2.16.0",
    license = "MIT",
    homepage = "https://www.freedesktop.org/wiki/Software/fontconfig/",
    description = "Font configuration and customization library",
    source = {
        url = "https://www.freedesktop.org/software/fontconfig/release/fontconfig-2.16.0.tar.xz",
        sha256 = "6a33dc555cc9ba8b10caf7695878ef134eeb36d0af366041f639b1da9b6ed220",
        strip = 1,
    },
    dependencies = {
        "freetype",
        "expat",
      },
    autotools = {
        args = {
          "--disable-shared",
          "--enable-static",
          "--disable-docs",
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
        "fontconfig",
      },
      binaries = {},
    },
}
