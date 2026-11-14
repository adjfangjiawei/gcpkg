-- spdlog 1.15.3 -- gcpkg port definition.
-- C++ logging on the external fmt port (CMAKE_PREFIX_PATH from deps).

local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "spdlog",
    version = "1.15.3",
    license = "MIT",
    homepage = "https://github.com/gabime/spdlog",
    description = "Fast C++ logging library on fmt",
    source = {
        url = "https://codeload.github.com/gabime/spdlog/tar.gz/refs/tags/v1.15.3",
        sha256 = "15a04e69c222eb6c01094b5c7ff8a249b36bb22788d72519646fb85feb267e67",
        strip = 1,
    },
    dependencies = {
        "fmt",
      },
    cmake = {
        defines = {
          SPDLOG_FMT_EXTERNAL = "ON",
          SPDLOG_BUILD_TESTS = "OFF",
          SPDLOG_BUILD_EXAMPLE = "OFF",
          BUILD_SHARED_LIBS = "OFF",
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
        "spdlog",
      },
      binaries = {},
    },
}
