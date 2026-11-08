-- lz4 1.10.0 -- Extremely fast compression library
-- Layer L0: no gcpkg dependencies. This is ordinary Lua; the
-- declarative recipe only removes boilerplate. Edit freely.
local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "lz4",
    version = "1.10.0",
    description = "Extremely fast compression library",
    license = "BSD-2-Clause",
    homepage = "https://github.com/lz4/lz4",
    source = {
        url = "https://github.com/lz4/lz4/releases/download/v1.10.0/lz4-1.10.0.tar.gz",
        sha256 = "537512904744b35e232912055ccf8ec66d768639ff3abe5788d90d792ec5f48b",
        strip = 1,
    },
    dependencies = {},
    cmake = {
        source = "build/cmake",
        defines = {
            LZ4_BUILD_CLI = "OFF",
        },
    },
    exports = {
        includes = { "@PREFIX@/include" },
        libdirs = { "@LIBDIR@" },
        libs = { "lz4" },
    },
}
