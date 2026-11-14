-- libass 0.17.5 -- gcpkg port definition.
-- Static subtitle renderer on source-built freetype/fribidi/harfbuzz/fontconfig.
-- License files are installed under share/doc/libass by gcpkg.r20.
local recipe = require("gcpkg.recipe")
local r20 = require("gcpkg.r20")

return recipe.meson {
    name = "libass",
    version = "0.17.5",
    license = "ISC",
    homepage = "https://github.com/libass/libass",
    description = "libass static subtitle renderer on source-built font/shaping ports",
    source = { url = "https://codeload.github.com/libass/libass/tar.gz/refs/tags/0.17.5", sha256 = "fa286fc9ee1ba3b932703a3df7b8474d01dc8abe29ec69b6fa68781dc4bf7acc", strip = 1 },
    dependencies = { "meson", "freetype", "fribidi", "harfbuzz", "fontconfig", "expat",
                     "bzip2", "brotli", "libpng", "zlib" },
    pre_build = function(ctx) r20.restrict_pkgconfig(ctx) end,
    meson = {
        options = {
            default_library = "static",
            test = "disabled", compare = "disabled", profile = "disabled",
            fuzz = "disabled", checkasm = "disabled",
            fontconfig = "enabled", directwrite = "disabled",
            coretext = "disabled", asm = "enabled",
            libunibreak = "disabled",
            ["require-system-font-provider"] = "false",
            ["large-tiles"] = "false",
        },
        auto_features = "disabled",
        buildtype = "release",
        wrap_mode = "nodownload",
        args = {},
    },
    exports = {
        includes = { "@PREFIX@/include" },
        libdirs = { "@LIBDIR@" },
        libs = { "ass" },
        binaries = {},
        link_flags = { "-lfreetype", "-lfribidi", "-lharfbuzz", "-lfontconfig",
                       "-lexpat", "-lz", "-lbz2", "-lbrotlidec", "-lbrotlienc",
                       "-lpng16", "-lm", "-lpthread", "-ldl" },
    },
    post_install = function(ctx) r20.license(ctx, { "COPYING" }) end,
}
