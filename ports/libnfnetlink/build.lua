-- libnfnetlink 1.0.2 -- gcpkg port definition.
-- Netfilter netlink base library.

local recipe = require("gcpkg.recipe")
local fs = require("gcpkg.fs")

return recipe.autotools {
    name = "libnfnetlink",
    version = "1.0.2",
    license = "GPL-2.0",
    homepage = "https://www.netfilter.org/projects/libnfnetlink/",
    description = "Netfilter netlink userspace library",
    source = {
        url = "https://www.netfilter.org/projects/libnfnetlink/files/libnfnetlink-1.0.2.tar.bz2",
        sha256 = "b064c7c3d426efb4786e60a8e6859b82ee2f2c5e49ffeea640cfe4fe33cbc376",
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
        "nfnetlink",
      },
      binaries = {},
    },
}
