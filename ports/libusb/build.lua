-- libusb 1.0.30 -- gcpkg port definition.
-- Userspace USB access: GitHub tag archives ship configure.ac, so pre_build runs autoreconf.

local recipe = require("gcpkg.recipe")
local fs = require("gcpkg.fs")

return recipe.autotools {
    name = "libusb",
    version = "1.0.30",
    license = "LGPL-2.1",
    homepage = "https://libusb.info",
    description = "Userspace USB device access library",
    source = {
        url = "https://codeload.github.com/libusb/libusb/tar.gz/refs/tags/v1.0.30",
        sha256 = "2ae28adb0bb9558c86135c4e1c11b320b0805461e207a64a6e520a114094bf07",
        strip = 1,
    },
    dependencies = {},
    autotools = {
        args = {
          "--disable-shared",
          "--enable-static",
          "--disable-udev",
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
        "@PREFIX@/include/libusb-1.0",
      },
      libdirs = {
        "@LIBDIR@",
      },
      libs = {
        "usb-1.0",
      },
      binaries = {},
    },
}
