-- mbedtls 3.6.7 -- ONE library, ONE build.lua + ONE features.yaml.
-- Verification: static registry/graph tests here; real builds for a
-- subset live in tests/linux-base.sh (GCPKG_BASE_DYNAMIC=1).
-- Alternative TLS stack built with CMake; tests/programs disabled.
-- Upstream is never patched: all adaptation is in this file.

local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "mbedtls",
    version = "3.6.7",
    license = "Apache-2.0",
    homepage = "https://www.trustedfirmware.org/projects/mbed-tls/",
    description = "Mbed TLS / PSA crypto library",
    source = {
        url = "https://codeload.github.com/Mbed-TLS/mbedtls/tar.gz/refs/tags/v3.6.7",
        sha256 = "7312b70b067b6a271961c8d36c3b8f9ba3e86fe6b26f18af13cd70430ee52ed1",
        strip = 1,
    },
    dependencies = {},
    cmake = {
        defines = {
          ENABLE_TESTING = "OFF",
          ENABLE_PROGRAMS = "OFF",
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
        "mbedtls",
        "mbedx509",
        "mbedcrypto",
      },
      binaries = {},
    },
}
