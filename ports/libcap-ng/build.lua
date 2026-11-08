-- Alternate Linux capabilities library
-- ONE library, ONE build.lua and ONE features.yaml. Upstream sources
-- are downloaded verbatim (sha256 verified) and never patched.
local recipe = require("gcpkg.recipe")

return recipe.autotools {
    name = "libcap-ng",
    version = "0.8.4",
    description = "Alternate Linux capabilities library",
    license = "LGPL-2.1",
    homepage = "https://github.com/stevegrubb/libcap-ng",
    source = {
        url = "https://github.com/stevegrubb/libcap-ng/archive/refs/tags/v0.8.4.tar.gz",
        sha256 = "5615c76a61039e283a6bd107c4faf345ae5ad4dcd45907defe5e474d8fdb6fd2",
        strip = 1,
    },
    dependencies = {},
    autotools = {
        args = { "--without-python", "--disable-shared" },
    },
    pre_build = function(ctx)
        require('gcpkg.fs').write(ctx.src .. '/NEWS', '')
        ctx.exec({ 'autoreconf', '-fi' }, { cwd = ctx.src, log = ctx.log })
    end,
    exports = {
      includes = { "@PREFIX@/include" },
      libdirs = { "@LIBDIR@" },
      libs = { "cap-ng", "drop_ambient" }
    },
}
