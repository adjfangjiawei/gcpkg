-- glib 2.84.4 -- ONE library, ONE build.lua + ONE features.yaml.
-- Verification: static registry/graph tests here; real builds for a
-- subset live in tests/linux-base.sh (GCPKG_BASE_DYNAMIC=1).
-- GLib core; Meson, depends on libffi + zlib + pcre2 (existing L0 ports).
-- Upstream is never patched: all adaptation is in this file.

local recipe = require("gcpkg.recipe")

return recipe.meson {
    name = "glib",
    version = "2.84.4",
    license = "LGPL-2.1",
    homepage = "https://docs.gtk.org/glib/",
    description = "GLib core application library",
    source = {
        url = "https://download.gnome.org/sources/glib/2.84/glib-2.84.4.tar.xz",
        sha256 = "8a9ea10943c36fc117e253f80c91e477b673525ae45762942858aef57631bb90",
        strip = 1,
    },
    dependencies = {
        "libffi",
        "zlib",
        "pcre2",
      },
    meson = {
        options = {
          tests = "false",
          installed_tests = "false",
        },
        args = {},
    },
    exports = {
      includes = {
        "@PREFIX@/include",
        "@PREFIX@/include/glib-2.0",
        "@LIBDIR@/glib-2.0/include",
      },
      libdirs = {
        "@LIBDIR@",
      },
      libs = {
        "glib-2.0",
        "gobject-2.0",
        "gio-2.0",
      },
      binaries = {},
    },
}
