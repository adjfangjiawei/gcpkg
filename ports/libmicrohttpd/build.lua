-- libmicrohttpd 1.0.1 -- ONE library, ONE build.lua + ONE features.yaml.
-- Verification: static registry/graph tests here; real builds for a
-- subset live in tests/linux-kernel.sh (GCPKG_KERNEL_DYNAMIC=1).
-- GNU embeddable HTTP server; depends on gnutls + libgcrypt.
-- Upstream is never patched: all adaptation is in this file.

local recipe = require("gcpkg.recipe")
local fs = require("gcpkg.fs")

return recipe.autotools {
    name = "libmicrohttpd",
    version = "1.0.1",
    license = "LGPL-2.1",
    homepage = "https://www.gnu.org/software/libmicrohttpd/",
    description = "GNU embeddable HTTP server library",
    source = {
        url = "https://ftp.gnu.org/gnu/libmicrohttpd/libmicrohttpd-1.0.1.tar.gz",
        sha256 = "a89e09fc9b4de34dde19f4fcb4faaa1ce10299b9908db1132bbfa1de47882b94",
        strip = 1,
    },
    dependencies = {
        "gnutls",
        "libgcrypt",
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
        "microhttpd",
      },
      binaries = {},
    },
}
