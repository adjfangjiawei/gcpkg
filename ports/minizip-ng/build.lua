-- minizip-ng 4.2.2 -- gcpkg port definition.
-- Modern zip library; zlib compression only, optional codecs/crypto off.

local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "minizip-ng",
    version = "4.2.2",
    license = "Zlib",
    homepage = "https://github.com/zlib-ng/minizip-ng",
    description = "Modern zip manipulation library with zlib compression",
    source = {
        url = "https://codeload.github.com/zlib-ng/minizip-ng/tar.gz/refs/tags/4.2.2",
        sha256 = "71af7b9799856d8b03619df3949e9c1be9703f8de0795af71399ba283cb27aac",
        strip = 1,
    },
    dependencies = {
        "zlib",
      },
    cmake = {
        defines = {
            BUILD_TESTING = "OFF",
            CMAKE_BUILD_TYPE = "Release",
            CMAKE_INSTALL_LIBDIR = "lib",
            BUILD_SHARED_LIBS = "OFF",
            MZ_COMPAT = "OFF",
            MZ_ZLIB = "ON",
            MZ_ZLIB_FLAVOR = "zlib",
            MZ_BZIP2 = "OFF",
            MZ_LZMA = "OFF",
            MZ_PPMD = "OFF",
            MZ_ZSTD = "OFF",
            MZ_OPENSSL = "OFF",
            MZ_LIBBSD = "OFF",
            MZ_ICONV = "OFF",
            MZ_PKCRYPT = "OFF",
            MZ_WZAES = "OFF",
            MZ_FETCH_LIBS = "OFF",
            MZ_FORCE_FETCH_LIBS = "OFF",
            MZ_BUILD_TESTS = "OFF",
            MZ_BUILD_UNIT_TESTS = "OFF",
            MZ_BUILD_FUZZ_TESTS = "OFF",
            MZ_CODE_COVERAGE = "OFF",
            MZ_SANITIZER = "OFF",
            MZ_FILE32_API = "OFF",
          },
        args = {},
        jobs = 2,
    },
    exports = {
      includes = { "@PREFIX@/include" },
      libdirs = { "@LIBDIR@" },
      libs = {
        "minizip-ng",
      },
      binaries = {},
      link_flags = {
        "-lz",
      },
    },
    post_install = function(ctx)
        local fs = require("gcpkg.fs")
        local util = require("gcpkg.util")
        local doc = util.join(ctx.prefix, "share", "doc", "minizip-ng")
        fs.mkdirs(doc)
            ctx.exec({ "cp", "-a", util.join(ctx.src, "LICENSE"), doc }, { log = ctx.log })
    end,
}
