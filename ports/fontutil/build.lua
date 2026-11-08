-- X.Org font-util: the fontutil.pc file and autoconf macros needed by the
-- X server build. It is a data-only port (no compiled translation units), but
-- pkg-config cannot resolve `dependency('fontutil')` without it.
-- ONE library, ONE build.lua and ONE features.yaml; upstream unmodified.
local recipe = require("gcpkg.recipe")

return recipe.autotools {
    name = "fontutil",
    version = "1.4.2",
    description = "X.Org font utilities: fontutil.pc and font macros (data-only port)",
    license = "MIT",
    homepage = "https://www.x.org",
    source = {
        url = "https://www.x.org/archive/individual/font/font-util-1.4.2.tar.xz",
        sha256 = "02e4f8afdcf03cc8372ca9c37aa104b1e36b47722dbc79531be08f0a4c622999",
        strip = 1,
    },
    dependencies = {},
    autotools = { args = {} },
    exports = {
        includes = { "@PREFIX@/include" },
    },
}
