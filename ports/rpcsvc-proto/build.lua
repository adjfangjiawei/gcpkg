-- rpcsvc-proto 1.4.4 -- ONE library, ONE build.lua + ONE features.yaml.
-- Verification: static registry/graph tests here; real builds for a
-- subset live in tests/linux-kernel.sh (GCPKG_KERNEL_DYNAMIC=1).
-- rpcgen protocol headers; no compiled library.
-- Upstream is never patched: all adaptation is in this file.

local recipe = require("gcpkg.recipe")
local fs = require("gcpkg.fs")

return recipe.autotools {
    name = "rpcsvc-proto",
    version = "1.4.4",
    license = "BSD-3-Clause",
    homepage = "https://github.com/thkukuk/rpcsvc-proto",
    description = "RPC protocol headers (rpcgen data)",
    source = {
        url = "https://codeload.github.com/thkukuk/rpcsvc-proto/tar.gz/refs/tags/v1.4.4",
        sha256 = "7988641deae8463303b6273d7af98ece09111c385d4c9134a142a5fad3cdfef8",
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
      libs = {},
      binaries = {},
    },
}
