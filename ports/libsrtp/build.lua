-- libsrtp 2.6.0 -- gcpkg port definition.
-- Secure RTP; `openssl` feature enables the OpenSSL crypto engine.

local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "libsrtp",
    version = "2.6.0",
    license = "BSD-3-Clause",
    homepage = "https://github.com/cisco/libsrtp",
    description = "Secure RTP/RTCP library",
    source = {
        url = "https://codeload.github.com/cisco/libsrtp/tar.gz/refs/tags/v2.6.0",
        sha256 = "bf641aa654861be10570bfc137d1441283822418e9757dc71ebb69a6cf84ea6b",
        strip = 1,
    },
    dependencies = {},
    cmake = {
        defines = {
          BUILD_TESTING = "OFF",
          LIBSRTP_TEST_APPS = "OFF",
          ENABLE_OPENSSL = "OFF",
          ENABLE_WARNINGS_AS_ERRORS = "OFF",
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
        "srtp2",
      },
      binaries = {},
    },
}
