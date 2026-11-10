-- docopt 0.6.3 -- gcpkg port definition.
-- C++11 docopt parser; static/shared library built with std::regex.

local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "docopt",
    version = "0.6.3",
    license = "MIT OR BSL-1.0",
    homepage = "https://github.com/docopt/docopt.cpp",
    description = "C++11 docopt command-line parser library",
    source = {
        url = "https://codeload.github.com/docopt/docopt.cpp/tar.gz/refs/tags/v0.6.3",
        sha256 = "28af5a0c482c6d508d22b14d588a3b0bd9ff97135f99c2814a5aa3cbff1d6632",
        strip = 1,
    },
    dependencies = {},
    cmake = {
        defines = {
            BUILD_TESTING = "OFF",
            CMAKE_BUILD_TYPE = "Release",
            CMAKE_INSTALL_LIBDIR = "lib",
            BUILD_SHARED_LIBS = "OFF",
            WITH_TESTS = "OFF",
            WITH_EXAMPLE = "OFF",
            USE_BOOST_REGEX = "OFF",
          },
        args = {},
    },
    exports = {
      includes = { "@PREFIX@/include" },
      libdirs = { "@LIBDIR@" },
      libs = {
        "docopt",
      },
      binaries = {},
      link_flags = {},
    },
    post_install = function(ctx)
        local fs = require("gcpkg.fs")
        local util = require("gcpkg.util")
        local doc = util.join(ctx.prefix, "share", "doc", "docopt")
        fs.mkdirs(doc)
            ctx.exec({ "cp", "-a", util.join(ctx.src, "LICENSE-Boost-1.0"), doc }, { log = ctx.log })
            ctx.exec({ "cp", "-a", util.join(ctx.src, "LICENSE-MIT"), doc }, { log = ctx.log })
    end,
}
