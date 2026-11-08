-- ncurses 6.5 -- ONE library, ONE build.lua + ONE features.yaml.
-- Verification: static registry/graph tests here; real builds for a
-- subset live in tests/linux-base.sh (GCPKG_BASE_DYNAMIC=1).
-- Terminal/terminfo library; readline depends on it.
-- Upstream is never patched: all adaptation is in this file.

local recipe = require("gcpkg.recipe")
local fs = require("gcpkg.fs")

return recipe.autotools {
    name = "ncurses",
    version = "6.5",
    license = "MIT-like",
    homepage = "https://invisible-island.net/ncurses/",
    description = "Terminal UI / terminfo library",
    source = {
        url = "https://ftp.gnu.org/gnu/ncurses/ncurses-6.5.tar.gz",
        sha256 = "136d91bc269a9a5785e5f9e980bc76ab57428f604ce3e5a5a90cebc767971cc6",
        strip = 1,
    },
    dependencies = {},
    autotools = {
        args = {
          "--disable-shared",
          "--enable-static",
          "--without-debug",
          "--enable-pc-files",
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
        "ncurses",
        "tinfo",
        "panel",
        "menu",
        "form",
      },
      binaries = {},
    },
}
