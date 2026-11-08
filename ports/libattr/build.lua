-- libattr 2.5.2 -- ONE library, ONE build.lua + ONE features.yaml.
-- Verification: static registry/graph tests here; real builds for a
-- subset live in tests/linux-base.sh (GCPKG_BASE_DYNAMIC=1).
-- Extended attributes (xattr) userspace library.
-- Upstream is never patched: all adaptation is in this file.

local recipe = require("gcpkg.recipe")
local fs = require("gcpkg.fs")

return recipe.autotools {
    name = "libattr",
    version = "2.5.2",
    license = "LGPL-2.1/GPL-2.0",
    homepage = "https://savannah.nongnu.org/projects/attr",
    description = "Extended attribute userspace library",
    source = {
        url = "https://download.savannah.nongnu.org/releases/attr/attr-2.5.2.tar.gz",
        sha256 = "39bf67452fa41d0948c2197601053f48b3d78a029389734332a6309a680c6c87",
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
        "attr",
      },
      binaries = {},
    },
}
