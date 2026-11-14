-- bzip3 1.4.0 -- gcpkg port definition.
-- bzip3 compression; static libbz3 without apps or native tuning.

local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "bzip3",
    version = "1.4.0",
    license = "LGPL-3.0-only",
    homepage = "https://github.com/kspalaiologos/bzip3",
    description = "High-ratio bzip3 compression library",
    source = {
        url = "https://codeload.github.com/kspalaiologos/bzip3/tar.gz/refs/tags/1.4.0",
        sha256 = "d70334c19c7cce2cc6c823566b7d8968ff08a52043d518f55caebd2e407b2233",
        strip = 1,
    },
    dependencies = {},
    cmake = {
        defines = {
            BUILD_TESTING = "OFF",
            CMAKE_BUILD_TYPE = "Release",
            CMAKE_INSTALL_LIBDIR = "lib",
            BUILD_SHARED_LIBS = "OFF",
            BZIP3_BUILD_APPS = "OFF",
            BZIP3_ENABLE_PTHREAD = "OFF",
            BZIP3_ENABLE_ARCH_NATIVE = "OFF",
            BZIP3_ENABLE_STATIC_EXE = "OFF",
          },
        args = {},
    },
    exports = {
      includes = { "@PREFIX@/include" },
      libdirs = { "@LIBDIR@" },
      libs = {
        "bzip3",
      },
      binaries = {},
      link_flags = {},
    },
    post_install = function(ctx)
        local fs = require("gcpkg.fs")
        local util = require("gcpkg.util")
        local doc = util.join(ctx.prefix, "share", "doc", "bzip3")
        fs.mkdirs(doc)
            ctx.exec({ "cp", "-a", util.join(ctx.src, "LICENSE"), doc }, { log = ctx.log })
            ctx.exec({ "cp", "-a", util.join(ctx.src, "libsais-LICENSE"), doc }, { log = ctx.log })
    end,
}
