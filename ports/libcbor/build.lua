-- libcbor 0.11.0 -- gcpkg port definition.
-- CBOR serialization; tests disabled.

local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "libcbor",
    version = "0.11.0",
    license = "MIT",
    homepage = "https://github.com/PJK/libcbor",
    description = "CBOR (RFC 7049) serialization library",
    source = {
        url = "https://codeload.github.com/PJK/libcbor/tar.gz/refs/tags/v0.11.0",
        sha256 = "89e0a83d16993ce50651a7501355453f5250e8729dfc8d4a251a78ea23bb26d7",
        strip = 1,
    },
    dependencies = {},
    cmake = {
        defines = {
          WITH_TESTS = "OFF",
          SANITIZE = "OFF",
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
        "cbor",
      },
      binaries = {},
    },
}
