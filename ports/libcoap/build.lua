-- libcoap 4.3.5 -- ONE library, ONE build.lua + ONE features.yaml.
-- Verification: static registry/graph tests in tests/r10.sh; real
-- builds in GCPKG_R10_DYNAMIC=1 ./tests/r10.sh.
-- CoAP RFC 7252; static libcoap-3, DTLS off by default.
-- Upstream is never patched: all adaptation is in this file.

local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "libcoap",
    version = "4.3.5",
    license = "BSD-2-Clause",
    homepage = "https://github.com/obgm/libcoap",
    description = "CoAP (RFC 7252) client/server library",
    source = {
        url = "https://codeload.github.com/obgm/libcoap/tar.gz/refs/tags/v4.3.5",
        sha256 = "a417ed26ec6c95c041b42353b5b6fad1602e2bf42a6e26c09863450e227b7b5f",
        strip = 1,
    },
    dependencies = {},
    cmake = {
        defines = {
          BUILD_TESTING = "OFF",
          ENABLE_DTLS = "OFF",
          ENABLE_DOCS = "OFF",
          ENABLE_EXAMPLES = "OFF",
          ENABLE_TESTS = "OFF",
          WITH_EPOLL = "OFF",
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
        "coap-3",
      },
      binaries = {},
    },
}
