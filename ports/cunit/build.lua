-- cunit 2.1-3 -- ONE library, ONE build.lua + ONE features.yaml.
-- Verification: static registry/graph tests in tests/r10.sh; real
-- builds in GCPKG_R10_DYNAMIC=1 ./tests/r10.sh.
-- Old automake Makefile hardcodes the author's path: autoreconf + ./configure regenerate it.
-- Upstream is never patched: all adaptation is in this file.

local recipe = require("gcpkg.recipe")
local fs = require("gcpkg.fs")

return recipe.autotools {
    name = "cunit",
    version = "2.1-3",
    license = "LGPL-2.1",
    homepage = "https://cunit.sourceforge.io",
    description = "Lightweight unit testing framework for C",
    source = {
        url = "https://sourceforge.net/projects/cunit/files/CUnit/2.1-3/CUnit-2.1-3.tar.bz2/download",
        sha256 = "f5b29137f845bb08b77ec60584fdb728b4e58f1023e6f249a464efa49a40f214",
        strip = 1,
    },
    dependencies = {},
    autotools = {
        args = {
          "--disable-shared",
          "--enable-static",
          "--disable-nls",
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
        "cunit",
      },
      binaries = {},
    },
}
