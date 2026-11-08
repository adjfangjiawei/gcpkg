-- libarchive 3.7.9 -- Layer L1 with a very wide L0 dependency surface:
-- zlib, bzip2, xz(lzma), zstd, lz4, openssl, expat, pcre2.
-- CMake's own FIND_PACKAGE() calls find them through CMAKE_PREFIX_PATH,
-- which gcpkg builds from every dependency manifest. No upstream patch.
local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "libarchive",
    version = "3.7.9",
    description = "Multi-format archive and compression library",
    license = "BSD-2-Clause",
    homepage = "https://www.libarchive.org",
    source = {
        url = "https://github.com/libarchive/libarchive/releases/download/v3.7.9/libarchive-3.7.9.tar.gz",
        sha256 = "aa90732c5a6bdda52fda2ad468ac98d75be981c15dde263d7b5cf6af66fd009f",
        strip = 1,
    },
    dependencies = {
        "zlib", "bzip2", "xz", "zstd", "lz4", "openssl", "expat", "pcre2",
    },
    cmake = {
        defines = {
            -- use the gcpkg-built lower-level libraries
            ENABLE_ZLIB = "ON",
            ENABLE_BZip2 = "ON",
            ENABLE_LZMA = "ON",
            ENABLE_ZSTD = "ON",
            ENABLE_LZ4 = "ON",
            ENABLE_OPENSSL = "ON",
            ENABLE_EXPAT = "ON",
            ENABLE_PCRE2POSIX = "ON",
            -- avoid unrelated system libraries
            ENABLE_LIBXML2 = "OFF",
            ENABLE_PCREPOSIX = "OFF",
            ENABLE_LIBB2 = "OFF",
            ENABLE_NETTLE = "OFF",
            ENABLE_MBEDTLS = "OFF",
            ENABLE_LZO = "OFF",
            ENABLE_CNG = "OFF",
            ENABLE_ICONV = "OFF",
            ENABLE_ACL = "OFF",
            ENABLE_XATTR = "OFF",
            -- library only, no tests / CLI tools
            ENABLE_TEST = "OFF",
            ENABLE_TAR = "OFF",
            ENABLE_CPIO = "OFF",
            ENABLE_CAT = "OFF",
            ENABLE_UNZIP = "OFF",
            ENABLE_WERROR = "OFF",
            ENABLE_INSTALL = "ON",
            BUILD_SHARED_LIBS = "OFF",
        },
    },
    exports = {
        includes = { "@PREFIX@/include" },
        libdirs = { "@LIBDIR@" },
        libs = { "archive" },
    },
}
