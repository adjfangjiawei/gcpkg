-- robin-map 1.3.0 -- ONE library, ONE build.lua + ONE features.yaml.
-- Static checks in tests/r11.sh; GCPKG_R11_DYNAMIC=1 builds it for real.
-- Header-only robin-hood hash map/set.
-- Upstream is never patched: all adaptation is in this file.

local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "robin-map",
    version = "1.3.0",
    license = "MIT",
    homepage = "https://github.com/Tessil/robin-map",
    description = "Header-only fast hash map/set (robin hood)",
    source = {
        url = "https://codeload.github.com/Tessil/robin-map/tar.gz/refs/tags/v1.3.0",
        sha256 = "a8424ad3b0affd4c57ed26f0f3d8a29604f0e1f2ef2089f497f614b1c94c7236",
        strip = 1,
    },
    dependencies = {},
    cmake = {
        defines = {
          BUILD_TESTING = "OFF",
          ROBIN_MAP_BUILD_TESTS = "OFF",
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
