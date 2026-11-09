-- libgcrypt 1.11.1 -- gcpkg port definition.
-- GNU crypto library; depends on libgpg-error.

local recipe = require("gcpkg.recipe")
local fs = require("gcpkg.fs")

return recipe.autotools {
    name = "libgcrypt",
    version = "1.11.1",
    license = "LGPL-2.1",
    homepage = "https://gnupg.org/software/libgcrypt/",
    description = "GNU cryptographic library",
    source = {
        url = "https://gnupg.org/ftp/gcrypt/libgcrypt/libgcrypt-1.11.1.tar.bz2",
        sha256 = "24e91c9123a46c54e8371f3a3a2502f1198f2893fbfbf59af95bc1c21499b00e",
        strip = 1,
    },
    dependencies = {
        "libgpg-error",
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
        "gcrypt",
      },
      binaries = {},
    },
}
