-- wolfssl 5.7.6 -- ONE library, ONE build.lua + ONE features.yaml.
-- Verification: static registry/graph tests here; real builds for a
-- subset live in tests/extra.sh (GCPKG_EXTRA_DYNAMIC=1).
-- Embedded TLS library; big tarball, autoreconf from configure.ac.
-- Upstream is never patched: all adaptation is in this file.

local recipe = require("gcpkg.recipe")
local fs = require("gcpkg.fs")

return recipe.autotools {
    name = "wolfssl",
    version = "5.7.6",
    license = "GPL-2.0",
    homepage = "https://www.wolfssl.com",
    description = "Embedded TLS/SSL library",
    source = {
        url = "https://codeload.github.com/wolfSSL/wolfssl/tar.gz/refs/tags/v5.7.6-stable",
        sha256 = "52b1e439e30d1ed8162a16308a8525a862183b67aa30373b11166ecbab000d63",
        strip = 1,
    },
    dependencies = {},
    autotools = {
        args = {
          "--disable-shared",
          "--enable-static",
          "--disable-examples",
          "--disable-crypttests",
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
        "wolfssl",
      },
      binaries = {},
    },
}
