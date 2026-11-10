-- elfutils 0.192 -- gcpkg port definition.
-- libelf/libdw on zlib + zstd + xz; debuginfod (HTTP server) disabled.

local recipe = require("gcpkg.recipe")
local fs = require("gcpkg.fs")

return recipe.autotools {
    name = "elfutils",
    version = "0.192",
    license = "LGPL-3.0/GPL-3.0",
    homepage = "https://sourceware.org/elfutils/",
    description = "libelf/libdw ELF and DWARF utilities",
    source = {
        url = "https://sourceware.org/elfutils/ftp/0.192/elfutils-0.192.tar.bz2",
        sha256 = "616099beae24aba11f9b63d86ca6cc8d566d968b802391334c91df54eab416b4",
        strip = 1,
    },
    dependencies = {
        "zlib",
        "zstd",
        "xz",
      },
    autotools = {
        args = {
          "--disable-shared",
          "--enable-static",
          "--disable-debuginfod",
          "--disable-libdebuginfod",
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
        "elf",
        "dw",
      },
      binaries = {},
    },
}
