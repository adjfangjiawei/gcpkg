-- fontconfig 2.16.0 -- ONE library, ONE build.lua + ONE features.yaml.
-- Verification: static registry/graph tests here; real builds for a
-- subset live in tests/linux-base.sh (GCPKG_BASE_DYNAMIC=1).
-- Font configuration on freetype + expat.
-- Upstream is never patched: all adaptation is in this file.

local recipe = require("gcpkg.recipe")
local fs = require("gcpkg.fs")

return recipe.autotools {
    name = "fontconfig",
    version = "2.16.0",
    license = "MIT",
    homepage = "https://www.freedesktop.org/wiki/Software/fontconfig/",
    description = "Font configuration and customization library",
    source = {
        url = "https://www.freedesktop.org/software/fontconfig/release/fontconfig-2.16.0.tar.xz",
        sha256 = "6a33dc555cc9ba8b10caf7695878ef134eeb36d0af366041f639b1da9b6ed220",
        strip = 1,
    },
    dependencies = {
        "freetype",
        "expat",
      },
    autotools = {
        args = {
          "--disable-shared",
          "--enable-static",
          "--disable-docs",
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
        "fontconfig",
      },
      binaries = {},
    },
}
