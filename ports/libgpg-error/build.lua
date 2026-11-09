-- libgpg-error 1.55 -- gcpkg port definition.
-- GnuPG common error/portability layer.

local recipe = require("gcpkg.recipe")
local fs = require("gcpkg.fs")

return recipe.autotools {
    name = "libgpg-error",
    version = "1.55",
    license = "LGPL-2.1",
    homepage = "https://gnupg.org/software/libgpg-error/",
    description = "GnuPG common error codes and portable helpers",
    source = {
        url = "https://gnupg.org/ftp/gcrypt/libgpg-error/libgpg-error-1.55.tar.bz2",
        sha256 = "95b178148863f07d45df0cea67e880a79b9ef71f5d230baddc0071128516ef78",
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
        "gpg-error",
      },
      binaries = {},
    },
}
