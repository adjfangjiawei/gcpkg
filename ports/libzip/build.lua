-- libzip 1.11.3 -- ONE library, ONE build.lua + ONE features.yaml.
-- Verification: static registry/graph tests here; real builds for a
-- subset live in tests/extra.sh (GCPKG_EXTRA_DYNAMIC=1).
-- ZIP library on the existing zlib port; `openssl` feature adds openssl.
-- Upstream is never patched: all adaptation is in this file.

local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "libzip",
    version = "1.11.3",
    license = "BSD-3-Clause",
    homepage = "https://libzip.org",
    description = "ZIP archive reading/writing on zlib",
    source = {
        url = "https://codeload.github.com/nih-at/libzip/tar.gz/refs/tags/v1.11.3",
        sha256 = "61bcfa2a852b59b7dc31a5c59c244a49a196df075805cfe6c1cfd09b3247990a",
        strip = 1,
    },
    dependencies = {
        "zlib",
      },
    cmake = {
        defines = {
          BUILD_TESTING = "OFF",
          BUILD_TOOLS = "OFF",
          BUILD_EXAMPLES = "OFF",
          BUILD_DOC = "OFF",
          ENABLE_OPENSSL = "OFF",
          ENABLE_GNUTLS = "OFF",
          ENABLE_MBEDTLS = "OFF",
          ENABLE_COMMONCRYPTO = "OFF",
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
        "zip",
      },
      binaries = {},
    },
}
