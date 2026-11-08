-- proxygen 2026.10.26.00 -- ONE library, ONE build.lua + ONE features.yaml.
-- Verification in this sandbox: static (check / graph / ports / externals) (see tests/media.sh).
-- Top of the Facebook stack: folly -> fizz -> wangle/mvfst -> proxygen (plus cmake and the L0 crypto/compression chain).
-- Upstream is never patched: all adaptation lives in this file.


local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "proxygen",
    version = "2026.10.26.00",
    description = "Facebook HTTP/2 / HTTP/3 server framework",
    license = "BSD-3-Clause",
    homepage = "https://github.com/facebook/proxygen",
    source = {
        url = "https://codeload.github.com/facebook/proxygen/tar.gz/refs/tags/v2026.10.26.00",
        sha256 = "a528e50d3bf7139cdc30bbcd73224f720dc3422849441a8231151262a3be2281",
        strip = 1,
    },
    dependencies = {
        "folly",
        "fizz",
        "wangle",
        "mvfst",
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
        "proxygen",
      },
      binaries = {},
    },
}
