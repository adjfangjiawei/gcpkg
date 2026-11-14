-- cpp-httplib 0.20.1 -- gcpkg port definition.
-- Header-only HTTP/HTTPS library; `tls` feature pulls openssl + zlib.

local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "cpp-httplib",
    version = "0.20.1",
    license = "MIT",
    homepage = "https://github.com/yhirose/cpp-httplib",
    description = "Header-only C++ HTTP/HTTPS client and server",
    source = {
        url = "https://codeload.github.com/yhirose/cpp-httplib/tar.gz/refs/tags/v0.20.1",
        sha256 = "b74b1c2c150be2841eba80192f64d93e9a6711985b3ae8aaa1a9cec4863d1dd9",
        strip = 1,
    },
    dependencies = {},
    cmake = {
        defines = {
          BUILD_TESTING = "OFF",
          HTTPLIB_INSTALL = "ON",
          HTTPLIB_COMPILE = "OFF",
          BUILD_SHARED_LIBS = "OFF",
          HTTPLIB_REQUIRE_OPENSSL = "OFF",
          HTTPLIB_REQUIRE_ZLIB = "OFF",
          HTTPLIB_REQUIRE_BROTLI = "OFF",
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
      libs = {},
      binaries = {},
    },
}
