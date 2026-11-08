-- cxxopts 3.2.0 -- ONE library, ONE build.lua + ONE features.yaml.
-- Static checks in tests/r11.sh; GCPKG_R11_DYNAMIC=1 builds it for real.
-- Header-only C++ option parser.
-- Upstream is never patched: all adaptation is in this file.

local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "cxxopts",
    version = "3.2.0",
    license = "MIT",
    homepage = "https://github.com/jarro2783/cxxopts",
    description = "Header-only C++ command-line option parser",
    source = {
        url = "https://codeload.github.com/jarro2783/cxxopts/tar.gz/refs/tags/v3.2.0",
        sha256 = "9f43fa972532e5df6c5fd5ad0f5bac606cdec541ccaf1732463d8070bbb7f03b",
        strip = 1,
    },
    dependencies = {},
    cmake = {
        defines = {
          BUILD_TESTING = "OFF",
          CXXOPTS_BUILD_EXAMPLES = "OFF",
          CXXOPTS_BUILD_TESTS = "OFF",
          CXXOPTS_ENABLE_INSTALL = "ON",
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
