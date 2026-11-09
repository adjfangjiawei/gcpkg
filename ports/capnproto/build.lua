-- capnproto 1.1.0 -- gcpkg port definition.
-- Cap'n Proto serialization/RPC; static libraries and capnp tools.

local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "capnproto",
    version = "1.1.0",
    license = "MIT",
    homepage = "https://capnproto.org",
    description = "Capability-based serialization and RPC library",
    source = {
        url = "https://codeload.github.com/capnproto/capnproto/tar.gz/refs/tags/v1.1.0",
        sha256 = "c0a0d78a07e821f7bae26c7fcac20a9202eb3d639a673b2606b76092a1f35b6b",
        strip = 1,
    },
    dependencies = {},
    cmake = {
        defines = {
          BUILD_TESTING = "OFF",
          CMAKE_BUILD_TYPE = "Release",
          CMAKE_INSTALL_LIBDIR = "lib",
          BUILD_SHARED_LIBS = "OFF",
          CAPNP_LITE = "OFF",
          EXTERNAL_CAPNP = "OFF",
        },
        args = {},
        jobs = 2,
    },
    exports = {
      includes = {
        "@PREFIX@/include",
      },
      libdirs = {
        "@LIBDIR@",
      },
      libs = {
        "capnp",
        "capnp-rpc",
        "capnp-json",
        "capnp-websocket",
        "capnpc",
        "kj",
        "kj-async",
        "kj-gzip",
        "kj-http",
        "kj-test",
        "kj-tls",
      },
      binaries = {
        "@PREFIX@/bin",
      },
    },
}
