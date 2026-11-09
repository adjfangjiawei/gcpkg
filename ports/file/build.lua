-- file 5.46 -- ONE library, ONE build.lua + ONE features.yaml.
-- Static registry checks in tests/r12.sh; GCPKG_R12_DYNAMIC=1 builds it for real.
-- libmagic file(1); stock autotools static build.
-- Upstream is never patched: all adaptation lives in this file.

local recipe = require("gcpkg.recipe")
local fs = require("gcpkg.fs")

return recipe.autotools {
    name = "file",
    version = "5.46",
    license = "BSD-2-Clause",
    homepage = "https://www.darwinsys.com/file/",
    description = "File type identification library and command",
    source = {
        url = "https://astron.com/pub/file/file-5.46.tar.gz",
        sha256 = "c9cc77c7c560c543135edc555af609d5619dbef011997e988ce40a3d75d86088",
        strip = 1,
    },
    dependencies = {},
    autotools = {
        args = {
          "--disable-bzlib",
          "--disable-xzlib",
          "--disable-zlib",
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
        "magic",
      },
      binaries = {
        "@PREFIX@/bin",
      },
    },
}
