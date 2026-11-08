-- libparted 3.6 -- ONE library, ONE build.lua + ONE features.yaml.
-- Verification: static registry/graph tests here; real builds for a
-- subset live in tests/linux-kernel.sh (GCPKG_KERNEL_DYNAMIC=1).
-- Partition table query/edit library; ships ./configure.
-- Upstream is never patched: all adaptation is in this file.

local recipe = require("gcpkg.recipe")
local fs = require("gcpkg.fs")

return recipe.autotools {
    name = "libparted",
    version = "3.6",
    license = "GPL-3.0",
    homepage = "https://www.gnu.org/software/parted/",
    description = "Partition table query/edit library (libparted)",
    source = {
        url = "https://ftp.gnu.org/gnu/parted/parted-3.6.tar.xz",
        sha256 = "3b43dbe33cca0f9a18601ebab56b7852b128ec1a3df3a9b30ccde5e73359e612",
        strip = 1,
    },
    dependencies = {
        "util-linux",
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
        "parted",
        "parted-fs-resize",
      },
      binaries = {},
    },
}
