-- xfsprogs 6.12.0 -- gcpkg port definition.
-- XFS userspace + libxfs; custom ./configure in tarball.

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
