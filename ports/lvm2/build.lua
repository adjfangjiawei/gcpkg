-- lvm2 2.03.43 -- ONE library, ONE build.lua + ONE features.yaml.
-- Verification: static registry/graph tests here; real builds for a
-- subset live in tests/linux-kernel.sh (GCPKG_KERNEL_DYNAMIC=1).
-- device-mapper / LVM2; configure in tarball, depends on util-linux + libaio.
-- Upstream is never patched: all adaptation is in this file.

local recipe = require("gcpkg.recipe")
local fs = require("gcpkg.fs")

return recipe.autotools {
    name = "lvm2",
    version = "2.03.43",
    license = "GPL-2.0/LGPL-2.1",
    homepage = "https://sourceware.org/lvm2/",
    description = "device-mapper / LVM2 and libdevmapper",
    source = {
        url = "https://codeload.github.com/lvmteam/lvm2/tar.gz/refs/tags/v2_03_43",
        sha256 = "e1732b3ffb885480f37addd65d2933c278f5182135b8b1305eba92851e13bc94",
        strip = 1,
    },
    dependencies = {
        "util-linux",
        "libaio",
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
        "devmapper",
        "lvm2cmd",
      },
      binaries = {},
    },
}
