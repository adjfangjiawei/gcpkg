-- libdecor 0.2.5 -- gcpkg port definition.
-- Static Wayland decoration library on source-built wayland/wayland-protocols.
-- License files are installed under share/doc/libdecor by gcpkg.r20.
local recipe = require("gcpkg.recipe")
local r20 = require("gcpkg.r20")

return recipe.meson {
    name = "libdecor",
    version = "0.2.5",
    license = "MIT",
    homepage = "https://gitlab.freedesktop.org/libdecor/libdecor",
    description = "libdecor static Wayland decoration library on source-built Wayland ports",
    source = { url = "https://gitlab.freedesktop.org/libdecor/libdecor/-/archive/0.2.5/libdecor-0.2.5.tar.gz", sha256 = "39c109a9a7eae943ba34d18a282c447d5729f9c486c8bc05ea305e4acd341522", strip = 1 },
    dependencies = { "meson", "wayland", "wayland-protocols" },
    pre_build = function(ctx) r20.libdecor_source_only_plugins(ctx) end,
    meson = {
        options = {
            default_library = "static",
            demo = "false", install_demo = "false",
            dbus = "disabled", gtk = "disabled",
        },
        auto_features = "disabled",
        buildtype = "release",
        wrap_mode = "nodownload",
        args = {},
    },
    exports = {
        includes = { "@PREFIX@/include" },
        libdirs = { "@LIBDIR@" },
        libs = { "decor-0" },
        binaries = {},
        link_flags = { "-lwayland-client" },
    },
    post_install = function(ctx) r20.license(ctx, { "LICENSE" }) end,
}
