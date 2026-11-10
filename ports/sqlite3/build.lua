-- sqlite3 3.46.1 -- gcpkg port definition.
-- SQLite amalgamation; autotools configure + make.

local recipe = require("gcpkg.recipe")
local fs = require("gcpkg.fs")

return recipe.autotools {
    name = "sqlite3",
    version = "3.46.1",
    license = "Public-Domain",
    homepage = "https://www.sqlite.org",
    description = "SQLite amalgamation (SQL database engine)",
    source = {
        url = "https://www.sqlite.org/2024/sqlite-autoconf-3460100.tar.gz",
        sha256 = "67d3fe6d268e6eaddcae3727fce58fcc8e9c53869bdd07a0c61e38ddf2965071",
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
        "sqlite3",
      },
      binaries = {
        "@PREFIX@/bin",
      },
    },
}
