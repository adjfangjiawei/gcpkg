-- libxslt 1.1.43 -- ONE library, ONE build.lua + ONE features.yaml.
-- Verification: static registry/graph tests here; real builds for a
-- subset live in tests/linux-base.sh (GCPKG_BASE_DYNAMIC=1).
-- XSLT processor on top of the existing libxml2 port.
-- Upstream is never patched: all adaptation is in this file.

local recipe = require("gcpkg.recipe")
local fs = require("gcpkg.fs")

return recipe.autotools {
    name = "libxslt",
    version = "1.1.43",
    license = "MIT-like",
    homepage = "https://gitlab.gnome.org/GNOME/libxslt",
    description = "XSLT 1.0 processor built on libxml2",
    source = {
        url = "https://download.gnome.org/sources/libxslt/1.1/libxslt-1.1.43.tar.xz",
        sha256 = "5a3d6b383ca5afc235b171118e90f5ff6aa27e9fea3303065231a6d403f0183a",
        strip = 1,
    },
    dependencies = {
        "libxml2",
      },
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
        "xslt",
        "exslt",
      },
      binaries = {},
    },
}
