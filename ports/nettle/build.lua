-- nettle 3.10 -- ONE library, ONE build.lua + ONE features.yaml.
-- Verification: static registry/graph tests here; real builds for a
-- subset live in tests/linux-base.sh (GCPKG_BASE_DYNAMIC=1).
-- Low-level crypto built on gmp.
-- Upstream is never patched: all adaptation is in this file.

local recipe = require("gcpkg.recipe")
local fs = require("gcpkg.fs")

return recipe.autotools {
    name = "nettle",
    version = "3.10",
    license = "LGPL-2.1",
    homepage = "https://www.lysator.liu.se/~nisse/nettle/",
    description = "Nettle low-level cryptographic library",
    source = {
        url = "https://ftp.gnu.org/gnu/nettle/nettle-3.10.tar.gz",
        sha256 = "b4c518adb174e484cb4acea54118f02380c7133771e7e9beb98a0787194ee47c",
        strip = 1,
    },
    dependencies = {
        "gmp",
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
        "nettle",
        "hogweed",
      },
      binaries = {},
    },
}
