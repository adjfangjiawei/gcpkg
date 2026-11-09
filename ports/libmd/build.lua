-- libmd 1.1.0 -- gcpkg port definition.
-- BSD message-digest routines; bottom of libbsd chain.

local recipe = require("gcpkg.recipe")
local fs = require("gcpkg.fs")

return recipe.autotools {
    name = "libmd",
    version = "1.1.0",
    license = "BSD-3-Clause",
    homepage = "https://github.com/guillemj/libmd",
    description = "Message digest functions from BSD systems",
    source = {
        url = "https://codeload.github.com/guillemj/libmd/tar.gz/refs/tags/1.1.0",
        sha256 = "2148e90c764085dfdeec3c0adf1551d893f78b24e487a29f3a0e630fefc9e22e",
        strip = 1,
    },
    dependencies = {},
    autotools = {
        args = {
          "--disable-shared",
          "--enable-static",
          "--disable-nls",
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
        "md",
      },
      binaries = {},
    },
}
