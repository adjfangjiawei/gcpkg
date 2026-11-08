-- msgpack 6.0.1 -- ONE library, ONE build.lua + ONE features.yaml.
-- Static checks in tests/r11.sh; GCPKG_R11_DYNAMIC=1 builds it for real.
-- MessagePack C/C++; exported as headers (uppercase OPTION() upstream).
-- Upstream is never patched: all adaptation is in this file.

local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "msgpack",
    version = "6.0.1",
    license = "BSL-1.0",
    homepage = "https://github.com/msgpack/msgpack-c",
    description = "MessagePack C/C++ serialization",
    source = {
        url = "https://github.com/msgpack/msgpack-c/releases/download/c-6.0.1/msgpack-c-6.0.1.tar.gz",
        sha256 = "a349cd9af28add2334c7009e331335af4a5b97d8558b2e9804d05f3b33d97925",
        strip = 1,
    },
    dependencies = {},
    cmake = {
        defines = {
          BUILD_TESTING = "OFF",
          MSGPACK_BUILD_TESTS = "OFF",
          MSGPACK_BUILD_EXAMPLES = "OFF",
          MSGPACK_GEN_COVERAGE = "OFF",
          MSGPACK_32BIT = "OFF",
          CMAKE_INSTALL_LIBDIR = "lib",
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
