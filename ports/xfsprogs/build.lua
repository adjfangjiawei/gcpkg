-- xfsprogs 6.12.0 -- ONE library, ONE build.lua + ONE features.yaml.
-- Verification: static registry/graph tests here; real builds for a
-- subset live in tests/linux-kernel.sh (GCPKG_KERNEL_DYNAMIC=1).
-- XFS userspace + libxfs; custom ./configure in tarball.
-- Upstream is never patched: all adaptation is in this file.

local recipe = require("gcpkg.recipe")
local fs = require("gcpkg.fs")

return recipe.autotools {
    name = "xfsprogs",
    version = "6.12.0",
    license = "GPL-2.0/LGPL-2.1",
    homepage = "https://xfs.wiki.kernel.org",
    description = "XFS filesystem tools and libxfs",
    source = {
        url = "https://mirrors.edge.kernel.org/pub/linux/utils/fs/xfs/xfsprogs/xfsprogs-6.12.0.tar.xz",
        sha256 = "0832407247db791cc70def96e7e254bd6edf043dc84a80a62f3ccd6e3dffd329",
        strip = 1,
    },
    dependencies = {
        "util-linux",
        "libattr",
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
        "xfs",
      },
      binaries = {},
    },
}
