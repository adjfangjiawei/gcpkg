-- libunibreak 5.1 -- ONE library, ONE build.lua + ONE features.yaml.
-- Verification: static registry/graph tests in tests/r10.sh; real
-- builds in GCPKG_R10_DYNAMIC=1 ./tests/r10.sh.
-- Unicode line/word breaking; needs autoreconf.
-- Upstream is never patched: all adaptation is in this file.

local recipe = require("gcpkg.recipe")
local fs = require("gcpkg.fs")

return recipe.autotools {
    name = "libunibreak",
    version = "5.1",
    license = "Zlib",
    homepage = "https://github.com/adah1972/libunibreak",
    description = "Unicode line/word breaking (UAX 14/29)",
    source = {
        url = "https://codeload.github.com/adah1972/libunibreak/tar.gz/refs/tags/libunibreak_5_1",
        sha256 = "d59878d82c84a60b592940a8e1a264f0a9714f0a9a8868b099846f780d9dc167",
        strip = 1,
    },
    dependencies = {},
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
        "unibreak",
      },
      binaries = {},
    },
}
