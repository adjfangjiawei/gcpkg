-- libwebsockets 4.3.3 -- gcpkg port definition.
-- Websockets/HTTP on zlib; `tls` feature adds openssl.

local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "libwebsockets",
    version = "4.3.3",
    license = "MIT",
    homepage = "https://libwebsockets.org",
    description = "Lightweight C websockets/http library",
    source = {
        url = "https://codeload.github.com/warmcat/libwebsockets/tar.gz/refs/tags/v4.3.3",
        sha256 = "6fd33527b410a37ebc91bb64ca51bdabab12b076bc99d153d7c5dd405e4bdf90",
        strip = 1,
    },
    dependencies = {
        "zlib",
      },
    cmake = {
        defines = {
          LWS_WITHOUT_TESTAPPS = "ON",
          LWS_WITHOUT_TEST_SERVER = "ON",
          LWS_WITHOUT_TEST_CLIENT = "ON",
          LWS_WITH_MINIMAL_EXAMPLES = "OFF",
          LWS_WITH_SSL = "OFF",
          LWS_WITH_SHARED = "OFF",
          LWS_WITH_STATIC = "ON",
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
        "websockets",
      },
      binaries = {},
    },
}
