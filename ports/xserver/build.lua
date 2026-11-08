-- X.Org X server (Xorg / Xvfb / Xephyr)
-- ONE library, ONE build.lua and ONE features.yaml. Upstream sources
-- are downloaded verbatim (sha256 verified) and never patched.
local recipe = require("gcpkg.recipe")

return recipe.meson {
    name = "xserver",
    version = "21.1.16",
    description = "X.Org X server (Xorg / Xvfb / Xephyr)",
    license = "MIT",
    homepage = "https://www.x.org",
    source = {
        url = "https://www.x.org/archive/individual/xserver/xorg-server-21.1.16.tar.xz",
        sha256 = "b14a116d2d805debc5b5b2aac505a279e69b217dae2fae2dfcb62400471a9970",
        strip = 1,
    },
    dependencies = { "xorgproto", "libX11", "libxcb", "libXau", "libXdmcp", "pixman", "libdrm", "libpciaccess", "dbus", "openssl", "libxkbcommon", "fontutil" },
    meson = {
        options = {
          default_library = "shared",
          xorg = "false",
          xephyr = "false",
          xvfb = "true",
          xnest = "false",
          glamor = "false",
          glx = "false",
          dri1 = "false",
          dri2 = "false",
          dri3 = "false",
          drm = "false",
          xv = "false",
          xvmc = "false",
          dga = "false",
          xinerama = "false",
          xace = "false",
          xselinux = "false",
          screensaver = "false",
          xres = "false",
          dpms = "false",
          mitshm = "false",
          int10 = "false",
          vgahw = "false",
          systemd_logind = "false",
          udev = "false",
          udev_kms = "false",
          hal = "false",
          agp = "false",
          xf86bigfont = "false",
          linux_apm = "false",
          linux_acpi = "false",
          ["secure-rpc"] = "false",
          suid_wrapper = "false",
          docs = "false",
          ["devel-docs"] = "false"
        },
        auto_features = "disabled",
    },
    exports = {
      includes = { "@PREFIX@/include/xorg", "@PREFIX@/include" },
      libdirs = { "@LIBDIR@" },
      binaries = { "@PREFIX@/bin" }
    },
}
