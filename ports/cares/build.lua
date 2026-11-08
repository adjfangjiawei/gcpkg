-- cares 1.34.5 -- Asynchronous DNS resolver library
-- Layer L0: no gcpkg dependencies. This is ordinary Lua; the
-- declarative recipe only removes boilerplate. Edit freely.
local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "cares",
    version = "1.34.5",
    description = "Asynchronous DNS resolver library",
    license = "MIT",
    homepage = "https://c-ares.org",
    source = {
        url = "https://github.com/c-ares/c-ares/releases/download/v1.34.5/c-ares-1.34.5.tar.gz",
        sha256 = "7d935790e9af081c25c495fd13c2cfcda4792983418e96358ef6e7320ee06346",
        strip = 1,
    },
    dependencies = {},
    cmake = {
        defines = {
            CARES_BUILD_TOOLS = "OFF",
            CARES_INSTALL = "ON",
        },
    },
    exports = {
        includes = { "@PREFIX@/include" },
        libdirs = { "@LIBDIR@" },
        libs = { "cares" },
    },
}
