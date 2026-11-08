-- libedit 3.1 -- ONE library, ONE build.lua + ONE features.yaml.
-- Verification: static registry/graph tests here; real builds for a
-- subset live in tests/extra.sh (GCPKG_EXTRA_DYNAMIC=1).
-- Editline library on the existing ncurses port.
-- Upstream is never patched: all adaptation is in this file.

local recipe = require("gcpkg.recipe")
local fs = require("gcpkg.fs")

return recipe.autotools {
    name = "libedit",
    version = "3.1",
    license = "BSD-3-Clause",
    homepage = "https://thrysoee.dk/editline/",
    description = "Command line editing library on ncurses",
    source = {
        url = "https://thrysoee.dk/editline/libedit-20250104-3.1.tar.gz",
        sha256 = "23792701694550a53720630cd1cd6167101b5773adddcb4104f7345b73a568ac",
        strip = 1,
    },
    dependencies = {
        "ncurses",
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
        "edit",
      },
      binaries = {},
    },
}
