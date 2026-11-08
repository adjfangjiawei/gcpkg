-- mpfr 4.2.2 -- ONE library, ONE build.lua + ONE features.yaml.
-- Verification: static registry/graph tests here; real builds for a
-- subset live in tests/linux-base.sh (GCPKG_BASE_DYNAMIC=1).
-- Needs gmp (dependency env supplies -I/-L/-lgmp).
-- Upstream is never patched: all adaptation is in this file.

local recipe = require("gcpkg.recipe")
local fs = require("gcpkg.fs")

return recipe.autotools {
    name = "mpfr",
    version = "4.2.2",
    license = "LGPL-3.0",
    homepage = "https://www.mpfr.org",
    description = "GNU MPFR multiple-precision floating point",
    source = {
        url = "https://ftp.gnu.org/gnu/mpfr/mpfr-4.2.2.tar.xz",
        sha256 = "b67ba0383ef7e8a8563734e2e889ef5ec3c3b898a01d00fa0a6869ad81c6ce01",
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
        "mpfr",
      },
      binaries = {},
    },
}
