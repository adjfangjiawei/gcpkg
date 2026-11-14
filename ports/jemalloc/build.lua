-- jemalloc 5.3.0 -- gcpkg port definition.
-- jemalloc; ships a generated configure.

local recipe = require("gcpkg.recipe")
local fs = require("gcpkg.fs")

return recipe.autotools {
    name = "jemalloc",
    version = "5.3.0",
    license = "BSD-2-Clause",
    homepage = "https://github.com/jemalloc/jemalloc",
    description = "Scalable concurrent malloc implementation",
    source = {
        url = "https://github.com/jemalloc/jemalloc/releases/download/5.3.0/jemalloc-5.3.0.tar.bz2",
        sha256 = "2db82d1e7119df3e71b7640219b6dfe84789bc0537983c3b7ac4f7189aecfeaa",
        strip = 1,
    },
    dependencies = {},
    autotools = {
        args = {
          "--disable-shared",
          "--enable-static",
          "--disable-examples",
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
        "jemalloc",
      },
      binaries = {
        "@PREFIX@/bin",
      },
    },
}
