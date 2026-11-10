-- libnetfilter_conntrack 1.0.9 -- gcpkg port definition.
-- Conntrack library on libnfnetlink + the existing libmnl port.

local recipe = require("gcpkg.recipe")
local fs = require("gcpkg.fs")

return recipe.autotools {
    name = "libnetfilter_conntrack",
    version = "1.0.9",
    license = "GPL-2.0",
    homepage = "https://www.netfilter.org/projects/libnetfilter_conntrack/",
    description = "Netfilter connection tracking library",
    source = {
        url = "https://www.netfilter.org/projects/libnetfilter_conntrack/files/libnetfilter_conntrack-1.0.9.tar.bz2",
        sha256 = "67bd9df49fe34e8b82144f6dfb93b320f384a8ea59727e92ff8d18b5f4b579a8",
        strip = 1,
    },
    dependencies = {
        "libnfnetlink",
        "libmnl",
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
        -- Static libbrotlidec needs libbrotlicommon; pkg-config does not add it.
        if ctx.name == "fontconfig" then
            ctx.env.LIBS = "-lbrotlicommon " .. (ctx.env.LIBS or "")
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
        "netfilter_conntrack",
      },
      binaries = {},
    },
}
