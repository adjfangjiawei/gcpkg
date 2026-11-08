-- libnet 1.3 -- ONE library, ONE build.lua + ONE features.yaml.
-- Verification: static registry/graph tests here; real builds for a
-- subset live in tests/extra.sh (GCPKG_EXTRA_DYNAMIC=1).
-- Packet construction; GitHub tag needs autoreconf first.
-- Upstream is never patched: all adaptation is in this file.

local recipe = require("gcpkg.recipe")
local fs = require("gcpkg.fs")

return recipe.autotools {
    name = "libnet",
    version = "1.3",
    license = "BSD-2-Clause",
    homepage = "https://github.com/libnet/libnet",
    description = "Packet construction and injection",
    source = {
        url = "https://codeload.github.com/libnet/libnet/tar.gz/refs/tags/v1.3",
        sha256 = "44e28a4e5a9256ce74d96fd1ad8ac2e3f300f55dc70c93bb81851183a21d7d3a",
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
        "net",
      },
      binaries = {},
    },
}
