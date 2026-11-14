-- ftxui v5.0.0 -- gcpkg port definition.
-- Functional terminal UI; three static libraries, tests/examples/docs off.

local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "ftxui",
    version = "v5.0.0",
    license = "MIT",
    homepage = "https://github.com/ArthurSonzogni/FTXUI",
    description = "C++ functional terminal UI library",
    source = {
        url = "https://codeload.github.com/ArthurSonzogni/FTXUI/tar.gz/refs/tags/v5.0.0",
        sha256 = "a2991cb222c944aee14397965d9f6b050245da849d8c5da7c72d112de2786b5b",
        strip = 1,
    },
    dependencies = {},
    cmake = {
        defines = {
            BUILD_TESTING = "OFF",
            CMAKE_BUILD_TYPE = "Release",
            CMAKE_INSTALL_LIBDIR = "lib",
            BUILD_SHARED_LIBS = "OFF",
            FTXUI_BUILD_EXAMPLES = "OFF",
            FTXUI_BUILD_DOCS = "OFF",
            FTXUI_BUILD_TESTS = "OFF",
            FTXUI_ENABLE_INSTALL = "ON",
            FTXUI_QUIET = "ON",
          },
        args = {},
    },
    exports = {
      includes = { "@PREFIX@/include" },
      libdirs = { "@LIBDIR@" },
      libs = {
        "ftxui-component",
        "ftxui-dom",
        "ftxui-screen",
      },
      binaries = {},
      link_flags = {
        "-pthread",
      },
    },
    post_install = function(ctx)
        local fs = require("gcpkg.fs")
        local util = require("gcpkg.util")
        local doc = util.join(ctx.prefix, "share", "doc", "ftxui")
        fs.mkdirs(doc)
            ctx.exec({ "cp", "-a", util.join(ctx.src, "LICENSE"), doc }, { log = ctx.log })
    end,
}
