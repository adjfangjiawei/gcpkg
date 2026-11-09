-- libtasn1 4.20.0 -- gcpkg port definition.
-- ASN.1 parser used by GnuTLS.

local recipe = require("gcpkg.recipe")
local fs = require("gcpkg.fs")

return recipe.autotools {
    name = "libtasn1",
    version = "4.20.0",
    license = "LGPL-2.1",
    homepage = "https://www.gnu.org/software/libtasn1/",
    description = "GNU ASN.1 parser library",
    source = {
        url = "https://ftp.gnu.org/gnu/libtasn1/libtasn1-4.20.0.tar.gz",
        sha256 = "92e0e3bd4c02d4aeee76036b2ddd83f0c732ba4cda5cb71d583272b23587a76c",
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
        "tasn1",
      },
      binaries = {},
    },
}
