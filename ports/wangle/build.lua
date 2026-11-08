-- wangle 2026.10.26.00 -- ONE library, ONE build.lua + ONE features.yaml.
-- Verification in this sandbox: static (check / graph / ports / externals) (see tests/media.sh).
-- Depends on folly + fizz from the same release line.
-- Upstream is never patched: all adaptation lives in this file.


local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "wangle",
    version = "2026.10.26.00",
    description = "Facebook C++ networking framework",
    license = "Apache-2.0",
    homepage = "https://github.com/facebook/wangle",
    source = {
        url = "https://codeload.github.com/facebook/wangle/tar.gz/refs/tags/v2026.10.26.00",
        sha256 = "5c482135fbea0ca6359c2093f1b725e5abfbed205fa59cecb0ed2fb9234cfbf3",
        strip = 1,
    },
    dependencies = {
        "folly",
        "fizz",
        "cmake",
      },
    cmake = {
        defines = {
          BUILD_TESTING = "OFF",
          BUILD_TESTS = "OFF",
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
        "wangle",
      },
      binaries = {},
    },
}
