-- civetweb v1.16 -- gcpkg port definition.
-- Embeddable web server; static C and C++ wrappers, SSL/tests/tools off.

local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "civetweb",
    version = "v1.16",
    license = "MIT",
    homepage = "https://github.com/civetweb/civetweb",
    description = "Embeddable C/C++ web server library",
    source = {
        url = "https://codeload.github.com/civetweb/civetweb/tar.gz/refs/tags/v1.16",
        sha256 = "f0e471c1bf4e7804a6cfb41ea9d13e7d623b2bcc7bc1e2a4dd54951a24d60285",
        strip = 1,
    },
    dependencies = {},
    cmake = {
        defines = {
            BUILD_TESTING = "OFF",
            CMAKE_BUILD_TYPE = "Release",
            CMAKE_INSTALL_LIBDIR = "lib",
            BUILD_SHARED_LIBS = "OFF",
            CIVETWEB_BUILD_TESTING = "OFF",
            CIVETWEB_ENABLE_SERVER_EXECUTABLE = "OFF",
            CIVETWEB_ENABLE_SSL = "OFF",
            CIVETWEB_ENABLE_ASAN = "OFF",
            CIVETWEB_ENABLE_CXX = "ON",
            CIVETWEB_ENABLE_LUA = "OFF",
            CIVETWEB_ENABLE_DUKTAPE = "OFF",
            CIVETWEB_ENABLE_WEBSOCKETS = "OFF",
            CIVETWEB_ENABLE_THIRD_PARTY_OUTPUT = "OFF",
          },
        args = {},
    },
    exports = {
      includes = { "@PREFIX@/include" },
      libdirs = { "@LIBDIR@" },
      libs = {
        "civetweb-cpp",
        "civetweb",
      },
      binaries = {},
      link_flags = {
        "-pthread",
      },
    },
    post_install = function(ctx)
        local fs = require("gcpkg.fs")
        local util = require("gcpkg.util")
        local doc = util.join(ctx.prefix, "share", "doc", "civetweb")
        fs.mkdirs(doc)
            ctx.exec({ "cp", "-a", util.join(ctx.src, "LICENSE.md"), doc }, { log = ctx.log })
    end,
}
