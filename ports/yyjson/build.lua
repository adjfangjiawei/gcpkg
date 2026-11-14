-- yyjson 0.10.0 -- gcpkg port definition.
-- Fast JSON reader/writer; CMake.

local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "yyjson",
    version = "0.10.0",
    license = "MIT",
    homepage = "https://github.com/ibireme/yyjson",
    description = "Fast JSON reader/writer in C",
    source = {
        url = "https://codeload.github.com/ibireme/yyjson/tar.gz/refs/tags/0.10.0",
        sha256 = "0d901cb2c45c5586e3f3a4245e58c2252d6b24bf4b402723f6179523d389b165",
        strip = 1,
    },
    dependencies = {},
    cmake = {
        defines = {
          BUILD_TESTING = "OFF",
          YYJSON_BUILD_TESTS = "OFF",
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
        "yyjson",
      },
      binaries = {},
    },
}
