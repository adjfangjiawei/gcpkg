-- nghttp3 1.11.0 -- gcpkg port definition.
-- HTTP/3 library; library-only CMake build.

local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "nghttp3",
    version = "1.11.0",
    license = "MIT",
    homepage = "https://github.com/ngtcp2/nghttp3",
    description = "HTTP/3 library (QUIC)",
    source = {
        url = "https://github.com/ngtcp2/nghttp3/releases/download/v1.11.0/nghttp3-1.11.0.tar.xz",
        sha256 = "27d084518f06d78279b050cc9cdff2418f80fb753da019427ce853cec920f33f",
        strip = 1,
    },
    dependencies = {},
    cmake = {
        defines = {
          ENABLE_LIB_ONLY = "ON",
          BUILD_TESTING = "OFF",
          BUILD_SHARED_LIBS = "OFF",
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
        "nghttp3",
      },
      binaries = {},
    },
}
