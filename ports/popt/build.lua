-- Command line option parsing library
-- ONE library, ONE build.lua and ONE features.yaml. Upstream sources
-- are downloaded verbatim (sha256 verified) and never patched.
local recipe = require("gcpkg.recipe")

return recipe.autotools {
    name = "popt",
    version = "1.19",
    description = "Command line option parsing library",
    license = "MIT",
    homepage = "https://github.com/rpm-software-management/popt",
    source = {
        url = "https://github.com/rpm-software-management/popt/archive/refs/tags/popt-1.19-release.tar.gz",
        sha256 = "6eb40d650526cb9fe63eb4415bcecdf9cf306f7556e77eff689abc5a44670060",
        strip = 1,
    },
    dependencies = {},
    autotools = {
        args = { "--disable-shared" },
    },
    pre_build = function(ctx)
        require('gcpkg.fs').write(ctx.src .. '/NEWS', '')
        ctx.exec({ 'autoreconf', '-fi' }, { cwd = ctx.src, log = ctx.log })
    end,
    exports = {
      includes = { "@PREFIX@/include" },
      libdirs = { "@LIBDIR@" },
      libs = { "popt" }
    },
}
