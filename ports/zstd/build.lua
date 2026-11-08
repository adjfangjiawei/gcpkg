-- zstd 1.5.7 -- Zstandard fast compression library
-- Layer L0: no gcpkg dependencies. This is ordinary Lua; the
-- declarative recipe only removes boilerplate. Edit freely.
local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "zstd",
    version = "1.5.7",
    description = "Zstandard fast compression library",
    license = "BSD-3-Clause OR GPL-2.0",
    homepage = "https://github.com/facebook/zstd",
    source = {
        url = "https://github.com/facebook/zstd/releases/download/v1.5.7/zstd-1.5.7.tar.gz",
        sha256 = "eb33e51f49a15e023950cd7825ca74a4a2b43db8354825ac24fc1b7ee09e6fa3",
        strip = 1,
    },
    dependencies = {},
    cmake = {
        source = "build/cmake",
        defines = {
            ZSTD_BUILD_PROGRAMS = "OFF",
            ZSTD_BUILD_CONTRIB = "OFF",
        },
    },
    exports = {
        includes = { "@PREFIX@/include" },
        libdirs = { "@LIBDIR@" },
        libs = { "zstd" },
    },
}
