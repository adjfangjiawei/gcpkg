-- glib 2.90.1 -- gcpkg port definition.
-- Latest GLib, static Meson build on libffi/zlib/pcre2 source ports; no system -dev packages.
-- License files are installed under share/doc/glib by gcpkg.r20.
local recipe = require("gcpkg.recipe")
local r20 = require("gcpkg.r20")
local util = require("gcpkg.util")

return recipe.meson {
    name = "glib",
    version = "2.90.1",
    license = "LGPL-2.1-or-later",
    homepage = "https://docs.gtk.org/glib/",
    description = "GLib 2.90.1 upgraded in place; static Meson build on source-built libffi/zlib/pcre2",
    source = { url = "https://download.gnome.org/sources/glib/2.90/glib-2.90.1.tar.xz", sha256 = "93c941aa17d5eb1d53fe838365f29a8b4e539c222a256d974ec8f30fc413e396", strip = 1 },
    dependencies = { "meson", "libffi", "zlib", "pcre2" },
    pre_build = function(ctx)
        r20.restrict_pkgconfig(ctx)
        -- glib's pinned proxy-libintl wrap may need a source download; use the
        -- explicit local proxy, never an apt package or a system -dev library.
        r20.enable_source_wrap_proxy(ctx)
    end,
    meson = {
        options = function(ctx)
            return {
                default_library = "static",
                tests = "false", installed_tests = "false",
                introspection = "disabled", ["man-pages"] = "disabled",
                documentation = "false",
                gtk_doc = "false", nls = "disabled", libmount = "disabled",
                selinux = "disabled", xattr = "false", libelf = "disabled",
                dtrace = "disabled", systemtap = "disabled", sysprof = "disabled",
                oss_fuzz = "disabled", glib_debug = "disabled",
                bsymbolic_functions = "false", force_posix_threads = "false",
                multiarch = "false", werror = "false",
                runtime_dir = util.join(ctx.prefix, "var/run"),
                gio_module_dir = util.join(ctx.prefix, "lib/gio/modules"),
                charsetalias_dir = util.join(ctx.prefix, "lib"),
            }
        end,
        auto_features = "disabled",
        buildtype = "release",
        wrap_mode = "default",
        args = {},
    },
    exports = {
        includes = { "@PREFIX@/include", "@PREFIX@/include/glib-2.0",
                     "@LIBDIR@/glib-2.0/include" },
        libdirs = { "@LIBDIR@" },
        libs = { "glib-2.0", "gobject-2.0", "gio-2.0" },
        binaries = {},
        link_flags = { "-lffi", "-lz", "-lpcre2-8", "-lpthread", "-lm", "-ldl" },
    },
    post_install = function(ctx) r20.license(ctx, { "COPYING", "LICENSES" }) end,
}
