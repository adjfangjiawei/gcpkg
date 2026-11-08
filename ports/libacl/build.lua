-- libacl 2.3.2 -- ONE library, ONE build.lua + ONE features.yaml.
-- Verification: static registry/graph tests here; real builds for a
-- subset live in tests/linux-base.sh (GCPKG_BASE_DYNAMIC=1).
-- POSIX ACL library, depends on libattr.
-- Upstream is never patched: all adaptation is in this file.

local recipe = require("gcpkg.recipe")
local fs = require("gcpkg.fs")

return recipe.autotools {
    name = "libacl",
    version = "2.3.2",
    license = "LGPL-2.1/GPL-2.0",
    homepage = "https://savannah.nongnu.org/projects/acl",
    description = "POSIX access control list library",
    source = {
        url = "https://download.savannah.nongnu.org/releases/acl/acl-2.3.2.tar.gz",
        sha256 = "5f2bdbad629707aa7d85c623f994aa8a1d2dec55a73de5205bac0bf6058a2f7c",
        strip = 1,
    },
    dependencies = {
        "libattr",
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
      },
      libdirs = {
        "@LIBDIR@",
      },
      libs = {
        "acl",
      },
      binaries = {},
    },
}
