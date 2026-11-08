-- libconfuse 3.4 -- ONE library, ONE build.lua + ONE features.yaml.
-- Verification: static registry/graph tests here; real builds for a
-- subset live in tests/linux-kernel.sh (GCPKG_KERNEL_DYNAMIC=1).
-- Config-file parser; tag archive needs autoreconf.
-- Upstream is never patched: all adaptation is in this file.

local recipe = require("gcpkg.recipe")
local fs = require("gcpkg.fs")

return recipe.autotools {
    name = "libconfuse",
    version = "3.4",
    license = "ISC",
    homepage = "https://github.com/martinh/libconfuse",
    description = "Configuration file parser library",
    source = {
        url = "https://codeload.github.com/martinh/libconfuse/tar.gz/refs/tags/v3.4",
        sha256 = "be97bf64ab8052ef874e6c2cfabd2dacf7ad76575bb12c7c42df3fd23675d151",
        strip = 1,
    },
    dependencies = {},
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
        "confuse",
      },
      binaries = {},
    },
}
