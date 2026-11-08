-- brotli 1.1.0 -- Brotli compression library
-- Layer L0: no gcpkg dependencies. This is ordinary Lua; the
-- declarative recipe only removes boilerplate. Edit freely.
local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "brotli",
    version = "1.1.0",
    description = "Brotli compression library",
    license = "MIT",
    homepage = "https://github.com/google/brotli",
    source = {
        url = "https://github.com/google/brotli/archive/refs/tags/v1.1.0.tar.gz",
        sha256 = "e720a6ca29428b803f4ad165371771f5398faba397edf6778837a18599ea13ff",
        strip = 1,
    },
    dependencies = {},
    cmake = {
        defines = {
            BROTLI_DISABLE_TESTS = "ON",
            BROTLI_BUILD_TOOLS = "OFF",
        },
    },
    exports = {
        includes = { "@PREFIX@/include" },
        libdirs = { "@LIBDIR@" },
        libs = { "brotlienc", "brotlidec", "brotlicommon" },
    },
}
