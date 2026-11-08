-- libtheora 1.1.1 -- ONE library, ONE build.lua + ONE features.yaml.
-- Verification: static registry/graph tests here; real builds for a
-- subset live in tests/extra.sh (GCPKG_EXTRA_DYNAMIC=1).
-- Official Xiph release tarball (ships configure); examples disabled.
-- Upstream is never patched: all adaptation is in this file.

local recipe = require("gcpkg.recipe")
local fs = require("gcpkg.fs")

return recipe.autotools {
    name = "libtheora",
    version = "1.1.1",
    license = "BSD-3-Clause",
    homepage = "https://xiph.org/theora/",
    description = "Theora video codec on libogg",
    source = {
        url = "https://downloads.xiph.org/releases/theora/libtheora-1.1.1.tar.xz",
        sha256 = "f36da409947aa2b3dcc6af0a8c2e3144bc19db2ed547d64e9171c59c66561c61",
        strip = 1,
    },
    dependencies = {
        "libogg",
      },
    autotools = {
        args = {
          "--disable-shared",
          "--enable-static",
          "--disable-examples",
          "--disable-oggtest",
          "--disable-vorbistest",
          "--disable-sdltest",
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
        "theora",
        "theoradec",
        "theoraenc",
      },
      binaries = {},
    },
}
