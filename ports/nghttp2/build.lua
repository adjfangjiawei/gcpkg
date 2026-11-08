-- nghttp2 1.65.0 -- Layer L1: HTTP/2 library, built lib-only.
local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "nghttp2",
    version = "1.65.0",
    description = "HTTP/2 C library",
    license = "MIT",
    homepage = "https://nghttp2.org",
    source = {
        url = "https://github.com/nghttp2/nghttp2/releases/download/v1.65.0/nghttp2-1.65.0.tar.gz",
        sha256 = "8ca4f2a77ba7aac20aca3e3517a2c96cfcf7c6b064ab7d4a0809e7e4e9eb9914",
        strip = 1,
    },
    dependencies = { "zlib" },
    cmake = {
        defines = {
            ENABLE_LIB_ONLY = "ON",
            ENABLE_APP = "OFF",
            ENABLE_EXAMPLES = "OFF",
            ENABLE_HPACK_TOOLS = "OFF",
            BUILD_TESTING = "OFF",
            BUILD_SHARED_LIBS = "OFF",
            BUILD_STATIC_LIBS = "ON",
        },
    },
    exports = {
        includes = { "@PREFIX@/include" },
        libdirs = { "@LIBDIR@" },
        libs = { "nghttp2" },
    },
}
