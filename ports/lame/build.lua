-- lame 3.100 -- gcpkg port definition.
-- Static MP3 encoder; frontend, decoder, GTK and shared library disabled.
-- License files are installed under share/doc/lame by gcpkg.r20.
local recipe = require("gcpkg.recipe")
local r20 = require("gcpkg.r20")

return recipe.autotools {
    name = "lame",
    version = "3.100",
    license = "LGPL-2.0-or-later",
    homepage = "https://lame.sourceforge.io/",
    description = "LAME 3.100 static MP3 encoder source port for FFmpeg",
    source = { url = "https://downloads.sourceforge.net/project/lame/lame/3.100/lame-3.100.tar.gz", sha256 = "ddfe36cab873794038ae2c1210557ad34857a4b6bdc515785d1da9e175b1da1e", strip = 1 },
    dependencies = {},
    autotools = {
        args = {
            "--disable-shared", "--enable-static", "--disable-frontend",
            "--disable-decoder",
            "--disable-gtktest", "--disable-rpath", "--disable-dependency-tracking",
        },
    },
    exports = {
        includes = { "@PREFIX@/include" },
        libdirs = { "@LIBDIR@" },
        libs = { "mp3lame" },
        binaries = {},
        link_flags = { "-lm" },
    },
    post_install = function(ctx) r20.license(ctx, { "LICENSE", "COPYING" }) end,
}
