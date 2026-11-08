-- libssh2 1.11.1 -- Layer L1: depends on openssl + zlib (both L0).
-- Dependency prefixes are visible automatically through CMAKE_PREFIX_PATH;
-- this port additionally pins the crypto backend explicitly.
local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "libssh2",
    version = "1.11.1",
    description = "SSH2 client library",
    license = "BSD-3-Clause",
    homepage = "https://www.libssh2.org",
    source = {
        url = "https://www.libssh2.org/download/libssh2-1.11.1.tar.gz",
        sha256 = "d9ec76cbe34db98eec3539fe2c899d26b0c837cb3eb466a56b0f109cabf658f7",
        strip = 1,
    },
    dependencies = { "openssl", "zlib" },
    cmake = {
        defines = function(ctx)
            local ssl = ctx.dep("openssl")
            return {
                CRYPTO_BACKEND = "OpenSSL",
                OPENSSL_ROOT_DIR = ssl and ssl.prefix or "",
                ENABLE_ZLIB_COMPRESSION = "ON",
                BUILD_TESTING = "OFF",
                BUILD_EXAMPLES = "OFF",
                BUILD_SHARED_LIBS = "OFF",
                BUILD_STATIC_LIBS = "ON",
                ENABLE_WERROR = "OFF",
                PICKY_COMPILER = "OFF",
            }
        end,
    },
    exports = {
        includes = { "@PREFIX@/include" },
        libdirs = { "@LIBDIR@" },
        libs = { "ssh2" },
    },
}
