-- libsecp256k1 0.6.0 -- ONE library, ONE build.lua + ONE features.yaml.
-- Verification: static registry/graph tests here; real builds for a
-- subset live in tests/extra.sh (GCPKG_EXTRA_DYNAMIC=1).
-- Optimised secp256k1 elliptic-curve library.
-- Upstream is never patched: all adaptation is in this file.

local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "libsecp256k1",
    version = "0.6.0",
    license = "MIT",
    homepage = "https://github.com/bitcoin-core/secp256k1",
    description = "Optimised elliptic-curve crypto",
    source = {
        url = "https://codeload.github.com/bitcoin-core/secp256k1/tar.gz/refs/tags/v0.6.0",
        sha256 = "785bb98e7d6705c51c8dfa8ac3af6aa2ccfa3774714d51c0b9e28fac1146e9f1",
        strip = 1,
    },
    dependencies = {},
    cmake = {
        defines = {
          SECP256K1_BUILD_TESTS = "OFF",
          SECP256K1_BUILD_BENCHMARK = "OFF",
          SECP256K1_BUILD_EXAMPLES = "OFF",
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
        "secp256k1",
      },
      binaries = {},
    },
}
