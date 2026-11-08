-- fmt 11.2.0 -- ONE library, ONE build.lua + ONE features.yaml.
-- Verification: static registry/graph tests here; real builds for a
-- subset live in tests/extra.sh (GCPKG_EXTRA_DYNAMIC=1).
-- C++ formatting library; bottom of the fmt -> spdlog chain.
-- Upstream is never patched: all adaptation is in this file.

local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "fmt",
    version = "11.2.0",
    license = "MIT",
    homepage = "https://fmt.dev",
    description = "Modern C++ formatting library",
    source = {
        url = "https://codeload.github.com/fmtlib/fmt/tar.gz/refs/tags/11.2.0",
        sha256 = "bc23066d87ab3168f27cef3e97d545fa63314f5c79df5ea444d41d56f962c6af",
        strip = 1,
    },
    dependencies = {},
    cmake = {
        defines = {
          FMT_TEST = "OFF",
          FMT_DOC = "OFF",
          FMT_INSTALL = "ON",
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
        "fmt",
      },
      binaries = {},
    },
}
