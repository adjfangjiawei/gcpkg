-- libaudit 3.1.5 -- gcpkg port definition.
-- Linux audit userspace; tag archive needs autoreconf.

local recipe = require("gcpkg.recipe")
local fs = require("gcpkg.fs")

return recipe.autotools {
    name = "libaudit",
    version = "3.1.5",
    license = "LGPL-2.1/GPL-2.0",
    homepage = "https://github.com/linux-audit/audit-userspace",
    description = "Linux audit userspace library",
    source = {
        url = "https://codeload.github.com/linux-audit/audit-userspace/tar.gz/refs/tags/v3.1.5",
        sha256 = "5b7b316baca9f5bd7fa860fecdc3915c919fd66f39950b33e203aefc43e0f4ef",
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
        "audit",
        "auparse",
      },
      binaries = {},
    },
}
