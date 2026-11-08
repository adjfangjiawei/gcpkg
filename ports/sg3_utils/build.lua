-- sg3_utils 1.48 -- ONE library, ONE build.lua + ONE features.yaml.
-- Verification: static registry/graph tests here; real builds for a
-- subset live in tests/linux-kernel.sh (GCPKG_KERNEL_DYNAMIC=1).
-- SCSI generic commands and libsgutils2; tag archive needs autoreconf.
-- Upstream is never patched: all adaptation is in this file.

local recipe = require("gcpkg.recipe")
local fs = require("gcpkg.fs")

return recipe.autotools {
    name = "sg3_utils",
    version = "1.48",
    license = "GPL-2.0/BSD-2-Clause",
    homepage = "https://sg.danny.cz/sg/sg3_utils.html",
    description = "SCSI generic command utilities and libsgutils2",
    source = {
        url = "https://codeload.github.com/hreinecke/sg3_utils/tar.gz/refs/tags/v1.48",
        sha256 = "694feed4fd22996cc265126439a8b6113ede80cd397a7bc7b24ba309fb4d751a",
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
        "sgutils2",
      },
      binaries = {},
    },
}
