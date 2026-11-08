-- libstoragemgmt 1.11.0 -- ONE library, ONE build.lua + ONE features.yaml.
-- Verification: static registry/graph tests here; real builds for a
-- subset live in tests/linux-kernel.sh (GCPKG_KERNEL_DYNAMIC=1).
-- Storage array management; autotools + autoreconf from tag archive.
-- Upstream is never patched: all adaptation is in this file.

local recipe = require("gcpkg.recipe")
local fs = require("gcpkg.fs")

return recipe.autotools {
    name = "libstoragemgmt",
    version = "1.11.0",
    license = "LGPL-2.1",
    homepage = "https://github.com/libstorage/libstoragemgmt",
    description = "Storage array management library",
    source = {
        url = "https://codeload.github.com/libstorage/libstoragemgmt/tar.gz/refs/tags/1.11.0",
        sha256 = "9abd55b76b99bafac5448eb1b57166d2ec633ff76c929db1473c85efb900dbab",
        strip = 1,
    },
    dependencies = {
        "glib",
        "libnvme",
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
        "storagemgmt",
      },
      binaries = {},
    },
}
