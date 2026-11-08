-- libdnet 1.12 -- ONE library, ONE build.lua + ONE features.yaml.
-- Verification: static registry/graph tests here; real builds for a
-- subset live in tests/extra.sh (GCPKG_EXTRA_DYNAMIC=1).
-- Low-level networking routines; ships a generated configure.
-- Upstream is never patched: all adaptation is in this file.

local recipe = require("gcpkg.recipe")
local fs = require("gcpkg.fs")

return recipe.autotools {
    name = "libdnet",
    version = "1.12",
    license = "BSD-3-Clause",
    homepage = "https://github.com/ofalk/libdnet",
    description = "Low-level networking routines",
    source = {
        url = "https://codeload.github.com/ofalk/libdnet/tar.gz/refs/tags/libdnet-1.12",
        sha256 = "b6360659c93fa2e3cde9e0a1fc9c07bc4111f3448c5de856e095eb98315dd424",
        strip = 1,
    },
    dependencies = {},
    autotools = {
        args = {
          "--disable-shared",
          "--enable-static",
          "--without-python",
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
        "dnet",
      },
      binaries = {},
    },
}
