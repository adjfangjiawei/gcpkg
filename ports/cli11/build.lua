-- cli11 2.4.2 -- ONE library, ONE build.lua + ONE features.yaml.
-- Static checks in tests/r11.sh; GCPKG_R11_DYNAMIC=1 builds it for real.
-- Header-only C++ command-line parser.
-- Upstream is never patched: all adaptation is in this file.

local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "cli11",
    version = "2.4.2",
    license = "BSD-3-Clause",
    homepage = "https://github.com/CLIUtils/CLI11",
    description = "Header-only C++ command-line parser",
    source = {
        url = "https://codeload.github.com/CLIUtils/CLI11/tar.gz/refs/tags/v2.4.2",
        sha256 = "f2d893a65c3b1324c50d4e682c0cdc021dd0477ae2c048544f39eed6654b699a",
        strip = 1,
    },
    dependencies = {},
    cmake = {
        defines = {
          BUILD_TESTING = "OFF",
          CLI11_BUILD_TESTS = "OFF",
          CLI11_BUILD_EXAMPLES = "OFF",
          CLI11_BUILD_DOCS = "OFF",
          CLI11_INSTALL = "ON",
          CLI11_PRECOMPILED = "OFF",
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
