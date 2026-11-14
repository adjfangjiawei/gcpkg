-- libuv 1.53.0 -- gcpkg port definition.
-- Cross-platform async I/O; CMake build.

local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "libuv",
    version = "1.53.0",
    license = "MIT",
    homepage = "https://libuv.org",
    description = "Cross-platform asynchronous I/O (Node.js libuv)",
    source = {
        url = "https://codeload.github.com/libuv/libuv/tar.gz/refs/tags/v1.53.0",
        sha256 = "279f3f67a24bb9921fe999ca6cd5e332fade8d515873ef9ba054b70e70a31d9e",
        strip = 1,
    },
    dependencies = {},
    cmake = {
        defines = {
          LIBUV_BUILD_TESTS = "OFF",
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
        "uv",
      },
      binaries = {},
    },
}
