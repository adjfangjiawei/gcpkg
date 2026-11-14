-- gnutls 3.8.9 -- gcpkg port definition.
-- Widest new dependency surface: nettle, gmp, libtasn1, libidn2, libunistring and the existing zlib port.

local recipe = require("gcpkg.recipe")
local fs = require("gcpkg.fs")

return recipe.autotools {
    name = "gnutls",
    version = "3.8.9",
    license = "LGPL-2.1",
    homepage = "https://www.gnutls.org",
    description = "GNU TLS library (alternative TLS stack)",
    source = {
        url = "https://www.gnupg.org/ftp/gcrypt/gnutls/v3.8/gnutls-3.8.9.tar.xz",
        sha256 = "69e113d802d1670c4d5ac1b99040b1f2d5c7c05daec5003813c049b5184820ed",
        strip = 1,
    },
    dependencies = {
        "nettle",
        "gmp",
        "libtasn1",
        "libidn2",
        "libunistring",
        "zlib",
      },
    autotools = {
        args = {
          "--disable-shared",
          "--enable-static",
          "--disable-doc",
          "--disable-guile",
          "--without-p11-kit",
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
        "gnutls",
      },
      binaries = {},
    },
}
