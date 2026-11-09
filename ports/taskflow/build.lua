-- taskflow 3.10.0 -- gcpkg port definition.
-- Header-only C++ task-graph parallelism library.

local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "taskflow",
    version = "3.10.0",
    license = "MIT",
    homepage = "https://github.com/taskflow/taskflow",
    description = "Header-only C++ parallel task programming library",
    source = {
        url = "https://codeload.github.com/taskflow/taskflow/tar.gz/refs/tags/v3.10.0",
        sha256 = "fe86765da417f6ceaa2d232ffac70c9afaeb3dc0816337d39a7c93e39c2dee0b",
        strip = 1,
    },
    dependencies = {},
    cmake = {
        defines = {
          BUILD_TESTING = "OFF",
          CMAKE_BUILD_TYPE = "Release",
          CMAKE_INSTALL_LIBDIR = "lib",
          BUILD_SHARED_LIBS = "OFF",
          TF_BUILD_TESTS = "OFF",
          TF_BUILD_EXAMPLES = "OFF",
          TF_BUILD_BENCHMARKS = "OFF",
          TF_BUILD_PROFILER = "OFF",
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
      libs = {},
      binaries = {},
    },
}
