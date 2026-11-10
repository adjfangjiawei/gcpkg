-- ada 2.9.2 -- gcpkg port definition.
-- WHATWG URL parser (C++20).

local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "ada",
    version = "2.9.2",
    license = "Apache-2.0",
    homepage = "https://github.com/ada-url/ada",
    description = "Fast WHATWG-compliant URL parser",
    source = {
        url = "https://codeload.github.com/ada-url/ada/tar.gz/refs/tags/v2.9.2",
        sha256 = "f41575ad7eec833afd9f6a0d6101ee7dc2f947fdf19ae8f1b54a71d59f4ba5ec",
        strip = 1,
    },
    dependencies = {},
    cmake = {
        -- Explicit results, like ports/sdl3/build.lua.  ADA_TOOLS defaults to
        -- ON upstream and would trigger find_package(Git) + CPM downloads;
        -- every option is stated here so configure neither probes nor fetches.
        defines = {
          BUILD_TESTING = "OFF",
          BUILD_SHARED_LIBS = "OFF",
          CMAKE_CXX_STANDARD = "17",
          ADA_TESTING = "OFF",
          ADA_BENCHMARKS = "OFF",
          ADA_TOOLS = "OFF",
          ADA_LOGGING = "OFF",
          ADA_DEVELOPMENT_CHECKS = "OFF",
          ADA_SANITIZE = "OFF",
          ADA_SANITIZE_UNDEFINED = "OFF",
          ADA_COVERAGE = "OFF",
          CODE_COVERAGE_VERBOSE = "FALSE",
          -- codecoverage.cmake check_cxx_compiler_flag result, stated directly.
          HAVE_fprofile_abs_path = "FALSE",
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
        "ada",
      },
      binaries = {},
    },
}
