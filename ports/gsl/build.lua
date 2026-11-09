-- gsl 2.8 -- gcpkg port definition.
-- GNU Scientific Library; stock autotools static build.

local recipe = require("gcpkg.recipe")
local fs = require("gcpkg.fs")

return recipe.autotools {
    name = "gsl",
    version = "2.8",
    license = "GPL-3.0-or-later",
    homepage = "https://www.gnu.org/software/gsl/",
    description = "GNU Scientific Library",
    source = {
        url = "https://ftp.gnu.org/gnu/gsl/gsl-2.8.tar.gz",
        sha256 = "6a99eeed15632c6354895b1dd542ed5a855c0f15d9ad1326c6fe2b2c9e423190",
        strip = 1,
    },
    dependencies = {},
    autotools = {
        args = {},
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
        "gsl",
        "gslcblas",
      },
      binaries = {
        "@PREFIX@/bin",
      },
    },
}
