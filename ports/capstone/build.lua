-- capstone 5.0.3 -- ONE library, ONE build.lua + ONE features.yaml.
-- Verification: static registry/graph tests here; real builds for a
-- subset live in tests/extra.sh (GCPKG_EXTRA_DYNAMIC=1).
-- Disassembly framework; static library only.
-- Upstream is never patched: all adaptation is in this file.

local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "capstone",
    version = "5.0.3",
    license = "BSD-3-Clause",
    homepage = "https://www.capstone-engine.org",
    description = "Multi-architecture disassembly framework",
    source = {
        url = "https://codeload.github.com/capstone-engine/capstone/tar.gz/refs/tags/5.0.3",
        sha256 = "3970c63ca1f8755f2c8e69b41432b710ff634f1b45ee4e5351defec4ec8e1753",
        strip = 1,
    },
    dependencies = {},
    cmake = {
        defines = {
          CAPSTONE_BUILD_TESTS = "OFF",
          CAPSTONE_BUILD_CSTOOL = "OFF",
          CAPSTONE_BUILD_SHARED = "OFF",
          CAPSTONE_BUILD_STATIC = "ON",
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
        "capstone",
      },
      binaries = {},
    },
}
