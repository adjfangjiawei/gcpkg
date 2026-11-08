-- libffi 3.4.8 -- Foreign function interface library
-- Layer L0: no gcpkg dependencies. This is ordinary Lua; the
-- declarative recipe only removes boilerplate. Edit freely.
local recipe = require("gcpkg.recipe")

return recipe.autotools {
    name = "libffi",
    version = "3.4.8",
    description = "Foreign function interface library",
    license = "MIT",
    homepage = "https://github.com/libffi/libffi",
    source = {
        url = "https://github.com/libffi/libffi/releases/download/v3.4.8/libffi-3.4.8.tar.gz",
        sha256 = "bc9842a18898bfacb0ed1252c4febcc7e78fa139fd27fdc7a3e30d9d9356119b",
        strip = 1,
    },
    dependencies = {},
    autotools = {
        args = { "--disable-docs", "--disable-multi-os-directory" },
    },
    exports = {
        includes = { "@PREFIX@/include" },
        libdirs = { "@LIBDIR@" },
        libs = { "ffi" },
    },
}
