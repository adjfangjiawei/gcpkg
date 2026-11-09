-- lcms2 2.16 -- gcpkg port definition.
-- Little CMS; disable optional host image codecs.

local recipe = require("gcpkg.recipe")
local fs = require("gcpkg.fs")

return recipe.autotools {
    name = "lcms2",
    version = "2.16",
    license = "MIT",
    homepage = "https://www.littlecms.com",
    description = "Little CMS color management engine",
    source = {
        url = "https://github.com/mm2/Little-CMS/releases/download/lcms2.16/lcms2-2.16.tar.gz",
        sha256 = "d873d34ad8b9b4cea010631f1a6228d2087475e4dc5e763eb81acc23d9d45a51",
        strip = 1,
    },
    dependencies = {},
    autotools = {
        args = {
          "--disable-shared",
          "--enable-static",
          "--without-jpeg",
          "--without-tiff",
          "--without-zlib",
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
        "lcms2",
      },
      binaries = {},
    },
}
