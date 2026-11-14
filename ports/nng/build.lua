-- nng v1.8.0 -- gcpkg port definition.
-- NNG messaging library; static build without TLS or tools.

local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "nng",
    version = "v1.8.0",
    license = "MIT",
    homepage = "https://github.com/nanomsg/nng",
    description = "Lightweight messaging and scalability protocols library",
    source = {
        url = "https://codeload.github.com/nanomsg/nng/tar.gz/refs/tags/v1.8.0",
        sha256 = "cfacfdfa35c1618a28bb940e71f774a513dcb91292999696b4346ad8bfb5baff",
        strip = 1,
    },
    dependencies = {},
    cmake = {
        defines = {
            BUILD_TESTING = "OFF",
            CMAKE_BUILD_TYPE = "Release",
            CMAKE_INSTALL_LIBDIR = "lib",
            BUILD_SHARED_LIBS = "OFF",
            NNG_TESTS = "OFF",
            NNG_TOOLS = "OFF",
            NNG_ENABLE_TLS = "OFF",
            NNG_ENABLE_NNGCAT = "OFF",
          },
        args = {},
    },
    exports = {
      includes = { "@PREFIX@/include" },
      libdirs = { "@LIBDIR@" },
      libs = {
        "nng",
      },
      binaries = {},
      link_flags = {
        "-pthread",
      },
    },
    post_install = function(ctx)
        local fs = require("gcpkg.fs")
        local util = require("gcpkg.util")
        local doc = util.join(ctx.prefix, "share", "doc", "nng")
        fs.mkdirs(doc)
            ctx.exec({ "cp", "-a", util.join(ctx.src, "LICENSE.txt"), doc }, { log = ctx.log })
    end,
}
