-- readline 8.2.13 -- gcpkg port definition.
-- GNU readline on top of ncurses.

local recipe = require("gcpkg.recipe")
local fs = require("gcpkg.fs")

return recipe.autotools {
    name = "readline",
    version = "8.2.13",
    license = "GPL-3.0",
    homepage = "https://www.gnu.org/software/readline/",
    description = "GNU readline line-editing library",
    source = {
        url = "https://ftp.gnu.org/gnu/readline/readline-8.2.13.tar.gz",
        sha256 = "0e5be4d2937e8bd9b7cd60d46721ce79f88a33415dd68c2d738fb5924638f656",
        strip = 1,
    },
    dependencies = {
        "ncurses",
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
    end,
    exports = {
      includes = {
        "@PREFIX@/include",
      },
      libdirs = {
        "@LIBDIR@",
      },
      libs = {
        "readline",
        "history",
      },
      binaries = {},
    },
}
