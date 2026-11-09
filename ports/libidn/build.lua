-- libidn 1.42 -- gcpkg port definition.
-- IDNA2003 stringprep library; GNU autotools.

local recipe = require("gcpkg.recipe")
local fs = require("gcpkg.fs")

return recipe.autotools {
    name = "libidn",
    version = "1.42",
    license = "LGPL-2.1",
    homepage = "https://www.gnu.org/software/libidn",
    description = "Internationalized domain-name (IDNA) library",
    source = {
        url = "https://ftp.gnu.org/gnu/libidn/libidn-1.42.tar.gz",
        sha256 = "d6c199dcd806e4fe279360cb4b08349a0d39560ed548ffd1ccadda8cdecb4723",
        strip = 1,
    },
    dependencies = {},
    autotools = {
        args = {
          "--disable-shared",
          "--enable-static",
          "--disable-nls",
          "--disable-doc",
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
        "idn",
      },
      binaries = {},
    },
}
