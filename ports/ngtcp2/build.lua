-- ngtcp2 1.16.0 -- gcpkg port definition.
-- QUIC library; `tls` feature pulls in the existing openssl port.

local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "ngtcp2",
    version = "1.16.0",
    license = "MIT",
    homepage = "https://github.com/ngtcp2/ngtcp2",
    description = "QUIC protocol implementation",
    source = {
        url = "https://codeload.github.com/ngtcp2/ngtcp2/tar.gz/refs/tags/v1.16.0",
        sha256 = "1f16fbd1c46cc8b8b76106ef890777dec73ef57c1cd567bf6d208f5a2c12ed5e",
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
        "ngtcp2",
      },
      binaries = {},
    },
}
