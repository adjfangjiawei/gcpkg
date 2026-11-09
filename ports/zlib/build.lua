-- zlib 1.3.1 -- General-purpose compression library
-- Layer L0: no gcpkg dependencies. This is ordinary Lua; the
-- declarative recipe only removes boilerplate. Edit freely.
local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "zlib",
    version = "1.3.1",
    description = "General-purpose compression library",
    license = "Zlib",
    homepage = "https://zlib.net",
    source = {
        url = "https://github.com/madler/zlib/releases/download/v1.3.1/zlib-1.3.1.tar.gz",
        sha256 = "9a93b2b7dfdac77ceba5a558a580e74667dd6fede4585b91eefb60f03b72df23",
        strip = 1,
    },
    dependencies = {},
    -- examples/no-examples are data-driven feature switches; the CMake
    -- adapter de-duplicates any repeated -DNAME=VALUE arguments.
    cmake = {},
    exports = {
        includes = { "@PREFIX@/include" },
        libdirs = { "@LIBDIR@" },
        libs = { "z" },
    },
}
