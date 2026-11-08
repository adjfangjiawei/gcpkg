-- xz 5.8.1 -- XZ / liblzma compression library
-- Layer L0: no gcpkg dependencies. This is ordinary Lua; the
-- declarative recipe only removes boilerplate. Edit freely.
local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "xz",
    version = "5.8.1",
    description = "XZ / liblzma compression library",
    license = "0BSD",
    homepage = "https://tukaani.org/xz/",
    source = {
        url = "https://github.com/tukaani-project/xz/releases/download/v5.8.1/xz-5.8.1.tar.gz",
        sha256 = "507825b599356c10dca1cd720c9d0d0c9d5400b9de300af00e4d1ea150795543",
        strip = 1,
    },
    dependencies = {},
    cmake = {
        defines = {
            XZ_NLS = "OFF",
            XZ_TOOL_XZDEC = "OFF",
            XZ_TOOL_LZMADEC = "OFF",
            XZ_TOOL_LZMAINFO = "OFF",
        },
    },
    exports = {
        includes = { "@PREFIX@/include" },
        libdirs = { "@LIBDIR@" },
        libs = { "lzma" },
    },
}
