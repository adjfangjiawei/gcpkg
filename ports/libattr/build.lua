-- libattr 2.5.2 -- gcpkg port definition.
-- Extended attributes (xattr) userspace library.

local recipe = require("gcpkg.recipe")
local fs = require("gcpkg.fs")

return recipe.autotools {
    name = "libattr",
    version = "2.5.2",
    license = "LGPL-2.1/GPL-2.0",
    homepage = "https://savannah.nongnu.org/projects/attr",
    description = "Extended attribute userspace library",
    source = {
        url = "https://download.savannah.nongnu.org/releases/attr/attr-2.5.2.tar.gz",
        sha256 = "39bf67452fa41d0948c2197601053f48b3d78a029389734332a6309a680c6c87",
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
        "attr",
      },
      binaries = {},
    },
}
