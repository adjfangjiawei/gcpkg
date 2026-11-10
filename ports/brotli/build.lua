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
        -- Explicit results, like ports/sdl3/build.lua: the only probes are
        -- BROTLI_EMSCRIPTEN and two CHECK_FUNCTION_EXISTS(log2) calls; on
        -- Linux log2 lives in libm.  BUILD_SHARED_LIBS defaults ON upstream.
        defines = {
            BUILD_SHARED_LIBS = "OFF",
            BUILD_TESTING = "OFF",
            CMAKE_BUILD_TYPE = "Release",
            BROTLI_DISABLE_TESTS = "ON",
            BROTLI_BUILD_TOOLS = "OFF",
            BROTLI_EMSCRIPTEN = "FALSE",
            LOG2_RES = "FALSE",
            LOG2_LIBM_RES = "TRUE",
        },
    },
    exports = {
        includes = { "@PREFIX@/include" },
        libdirs = { "@LIBDIR@" },
        libs = { "brotlienc", "brotlidec", "brotlicommon" },
    },
}
