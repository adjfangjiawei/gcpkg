-- udisks2 2.11.2 -- ONE library, ONE build.lua + ONE features.yaml.
-- Verification: static registry/graph tests here; real builds for a
-- subset live in tests/linux-kernel.sh (GCPKG_KERNEL_DYNAMIC=1).
-- Widest disk-info dependency surface: glib, dbus, libgudev, libatasmart, libnvme (-> liburing), libparted, util-linux, libacl.
-- Upstream is never patched: all adaptation is in this file.

local recipe = require("gcpkg.recipe")
local fs = require("gcpkg.fs")

return recipe.autotools {
    name = "udisks2",
    version = "2.11.2",
    license = "GPL-2.0",
    homepage = "https://github.com/storaged-project/udisks",
    description = "D-Bus disk information/query service (widest storage dependency surface)",
    source = {
        url = "https://codeload.github.com/storaged-project/udisks/tar.gz/refs/tags/udisks-2.11.2",
        sha256 = "1e2c6db7c68a5f72c0810db823aa1422ba66f19502a9e00a70ba72db7bcfd85f",
        strip = 1,
    },
    dependencies = {
        "glib",
        "dbus",
        "libgudev",
        "libatasmart",
        "libnvme",
        "libparted",
        "util-linux",
        "libacl",
      },
    autotools = {
        args = {
          "--disable-shared",
          "--enable-static",
          "--disable-gtk-doc",
          "--disable-introspection",
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
        "udisks2",
      },
      binaries = {},
    },
}
