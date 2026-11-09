-- meshoptimizer v0.22 -- gcpkg port definition.
-- Mesh optimization; static library and public header only.

local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "meshoptimizer",
    version = "v0.22",
    license = "MIT",
    homepage = "https://github.com/zeux/meshoptimizer",
    description = "Mesh optimization and simplification library",
    source = {
        url = "https://codeload.github.com/zeux/meshoptimizer/tar.gz/refs/tags/v0.22",
        sha256 = "e296cf0685b6421f84bd8a44d0a3cca82a219500f11c793dfbb6087ec86bb1a3",
        strip = 1,
    },
    dependencies = {},
    cmake = {
        defines = {
            BUILD_TESTING = "OFF",
            CMAKE_BUILD_TYPE = "Release",
            CMAKE_INSTALL_LIBDIR = "lib",
            BUILD_SHARED_LIBS = "OFF",
            MESHOPT_BUILD_DEMO = "OFF",
            MESHOPT_BUILD_GLTFPACK = "OFF",
            MESHOPT_BUILD_SHARED_LIBS = "OFF",
            MESHOPT_WERROR = "OFF",
          },
        args = {},
        jobs = 2,
    },
    exports = {
      includes = { "@PREFIX@/include" },
      libdirs = { "@LIBDIR@" },
      libs = {
        "meshoptimizer",
      },
      binaries = {},
      link_flags = {},
    },
    post_install = function(ctx)
        local fs = require("gcpkg.fs")
        local util = require("gcpkg.util")
        local doc = util.join(ctx.prefix, "share", "doc", "meshoptimizer")
        fs.mkdirs(doc)
            ctx.exec({ "cp", "-a", util.join(ctx.src, "LICENSE.md"), doc }, { log = ctx.log })
    end,
}
