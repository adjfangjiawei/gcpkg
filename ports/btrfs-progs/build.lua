-- btrfs-progs 6.19.1 -- gcpkg port definition.
-- Btrfs tools on util-linux/zlib/zstd/lz4; tag archive needs autogen.sh.

local recipe = require("gcpkg.recipe")
local fs = require("gcpkg.fs")

return recipe.autotools {
    name = "btrfs-progs",
    version = "6.19.1",
    license = "GPL-2.0",
    homepage = "https://btrfs.readthedocs.io",
    description = "Btrfs filesystem userspace tools and libbtrfs",
    source = {
        url = "https://codeload.github.com/kdave/btrfs-progs/tar.gz/refs/tags/v6.19.1",
        sha256 = "3213ab1c1f92a75ff181a08009bbb66a4899e168fdb57ca92a5f3045835e169c",
        strip = 1,
    },
    dependencies = {
        "util-linux",
        "zlib",
        "zstd",
        "lz4",
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
        "btrfs",
      },
      binaries = {},
    },
}
