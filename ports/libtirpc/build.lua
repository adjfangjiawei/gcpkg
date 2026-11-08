-- libtirpc 1.3.6 -- ONE library, ONE build.lua + ONE features.yaml.
-- Verification: static registry/graph tests here; real builds for a
-- subset live in tests/linux-kernel.sh (GCPKG_KERNEL_DYNAMIC=1).
-- TI-RPC; ships ./configure, depends on rpcsvc-proto headers.
-- Upstream is never patched: all adaptation is in this file.

local recipe = require("gcpkg.recipe")
local fs = require("gcpkg.fs")

return recipe.autotools {
    name = "libtirpc",
    version = "1.3.6",
    license = "BSD-3-Clause",
    homepage = "https://sourceforge.net/projects/libtirpc/",
    description = "Transport-independent RPC library",
    source = {
        url = "https://downloads.sourceforge.net/project/libtirpc/libtirpc/1.3.6/libtirpc-1.3.6.tar.bz2",
        sha256 = "bbd26a8f0df5690a62a47f6aa30f797f3ef8d02560d1bc449a83066b5a1d3508",
        strip = 1,
    },
    dependencies = {
        "rpcsvc-proto",
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
        "@PREFIX@/include/tirpc",
      },
      libdirs = {
        "@LIBDIR@",
      },
      libs = {
        "tirpc",
      },
      binaries = {},
    },
}
