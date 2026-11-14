-- expat 2.7.1 -- XML parser library
-- Layer L0: no gcpkg dependencies. This is ordinary Lua; the
-- declarative recipe only removes boilerplate. Edit freely.
local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "expat",
    version = "2.7.1",
    description = "XML parser library",
    license = "MIT",
    homepage = "https://libexpat.github.io",
    source = {
        url = "https://github.com/libexpat/libexpat/releases/download/R_2_7_1/expat-2.7.1.tar.gz",
        sha256 = "0cce2e6e69b327fc607b8ff264f4b66bdf71ead55a87ffd5f3143f535f15cfa2",
        strip = 1,
    },
    dependencies = {},
    cmake = {
        defines = {
            EXPAT_BUILD_TOOLS = "OFF",
            EXPAT_BUILD_EXAMPLES = "OFF",
            EXPAT_BUILD_DOCS = "OFF",
            EXPAT_BUILD_FUZZERS = "OFF",
        },
    },
    exports = {
        includes = { "@PREFIX@/include" },
        libdirs = { "@LIBDIR@" },
        libs = { "expat" },
    },
}
