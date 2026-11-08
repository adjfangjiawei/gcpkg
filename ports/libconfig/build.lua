-- libconfig 1.7.3 -- ONE library, ONE build.lua + ONE features.yaml.
-- Verification: static registry/graph tests here; real builds for a
-- subset live in tests/extra.sh (GCPKG_EXTRA_DYNAMIC=1).
-- Structured config parser; docs/examples/tests off (no makeinfo).
-- Upstream is never patched: all adaptation is in this file.

local recipe = require("gcpkg.recipe")
local fs = require("gcpkg.fs")

return recipe.autotools {
    name = "libconfig",
    version = "1.7.3",
    license = "LGPL-2.1",
    homepage = "https://hyperrealm.github.io/libconfig/",
    description = "Structured configuration file parser",
    source = {
        url = "https://codeload.github.com/hyperrealm/libconfig/tar.gz/refs/tags/v1.7.3",
        sha256 = "68757e37c567fd026330c8a8449aa5f9cac08a642f213f2687186b903bd7e94e",
        strip = 1,
    },
    dependencies = {},
    autotools = {
        args = {
          "--disable-shared",
          "--enable-static",
          "--disable-doc",
          "--disable-examples",
          "--disable-tests",
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
        "config",
      },
      binaries = {},
    },
}
