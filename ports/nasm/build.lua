-- nasm 2.16.03 -- tool port: exports bin/ so dependents get nasm on PATH.
-- Tool port: exports bin/ so dependents get nasm on PATH.
local recipe = require("gcpkg.recipe")
return recipe.autotools {
    name = "nasm",
    version = "2.16.03",
    license = "BSD-2-Clause",
    homepage = "https://www.nasm.us",
    description = "Netwide Assembler (nasm/ndisasm), built from source as a tool port",
    source = {
        url = "https://www.nasm.us/pub/nasm/releasebuilds/2.16.03/nasm-2.16.03.tar.xz",
        sha256 = "1412a1c760bbd05db026b6c0d1657affd6631cd0a63cddb6f73cc6d4aa616148",
        strip = 1,
    },
    dependencies = {},
    autotools = { args = {} },
    exports = {
        includes = {},
        libdirs = {},
        libs = {},
        binaries = { "@PREFIX@/bin" },
    },
}
