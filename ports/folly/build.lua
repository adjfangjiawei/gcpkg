-- folly 2026.10.26.00 -- gcpkg port definition.
-- Wide dependency surface: reuses the existing gcpkg L0 chain (cmake, openssl, zlib, zstd, lz4, bzip2). boost/glog/gflags/fmt/double-conversion/libevent come from the host pkgconfig backend.


local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "folly",
    version = "2026.10.26.00",
    description = "Facebook C++ foundation library",
    license = "Apache-2.0",
    homepage = "https://github.com/facebook/folly",
    source = {
        url = "https://codeload.github.com/facebook/folly/tar.gz/refs/tags/v2026.10.26.00",
        sha256 = "b47fe04b804adfb51c65cda6b171505e67b9d1d69621106e54697821d1bf7ebc",
        strip = 1,
    },
    dependencies = {
        "cmake",
        "openssl",
        "zlib",
        "zstd",
        "lz4",
        "bzip2",
      },
    cmake = {
        defines = {
          BUILD_TESTING = "OFF",
          BUILD_TESTS = "OFF",
        },
        args = {},
    },
    exports = {
      includes = {
        "@PREFIX@/include",
      },
      libdirs = {
        "@LIBDIR@",
      },
      libs = {
        "folly",
      },
      binaries = {},
    },
}
