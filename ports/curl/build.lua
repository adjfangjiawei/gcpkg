-- curl 8.13.0 -- Layer L2: depends on L0 compression/TLS libraries AND on
-- L1 libraries (nghttp2, libssh2). gcpkg builds the whole DAG bottom-up and
-- injects CMAKE_PREFIX_PATH / PKG_CONFIG_PATH so CMake's own find_package()
-- and pkg-config discover every dependency without patching curl.
local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "curl",
    version = "8.13.0",
    description = "libcurl: multi-protocol file transfer library",
    license = "curl",
    homepage = "https://curl.se",
    source = {
        url = "https://curl.se/download/curl-8.13.0.tar.gz",
        sha256 = "c261a4db579b289a7501565497658bbd52d3138fdbaccf1490fa918129ab45bc",
        strip = 1,
    },
    dependencies = {
        "openssl", "zlib", "brotli", "zstd", "cares", "nghttp2", "libssh2",
    },
    cmake = {
        defines = function(ctx)
            local ssl = ctx.dep("openssl")
            return {
                CURL_USE_OPENSSL = "ON",
                OPENSSL_ROOT_DIR = ssl and ssl.prefix or "",
                CURL_ZLIB = "ON",
                CURL_BROTLI = "ON",
                CURL_ZSTD = "ON",
                USE_NGHTTP2 = "ON",
                USE_LIBSSH2 = "ON",
                ENABLE_ARES = "ON",
                -- keep the build self-contained: do not pick up random system libs
                CURL_USE_LIBPSL = "OFF",
                USE_LIBIDN2 = "OFF",
                CURL_USE_GSSAPI = "OFF",
                CURL_USE_LIBSSH = "OFF",
                USE_LIBRTMP = "OFF",
                -- otherwise CMake picks up the host's OpenLDAP and the static
                -- libcurl would need -lldap/-llber from outside the DAG
                CURL_DISABLE_LDAP = "ON",
                CURL_DISABLE_LDAPS = "ON",
                USE_OPENLDAP = "OFF",
                BUILD_CURL_EXE = "OFF",
                BUILD_SHARED_LIBS = "OFF",
                BUILD_STATIC_LIBS = "ON",
                BUILD_TESTING = "OFF",
                CURL_DISABLE_INSTALL = "OFF",
                CURL_WERROR = "OFF",
                PICKY_COMPILER = "OFF",
            }
        end,
    },
    exports = {
        includes = { "@PREFIX@/include", "@PREFIX@/include/curl" },
        libdirs = { "@LIBDIR@" },
        libs = { "curl" },
        link_flags = { "-lpthread", "-ldl" },
    },
}
