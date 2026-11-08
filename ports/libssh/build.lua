-- libssh 0.11.1 -- ONE library, ONE build.lua + ONE features.yaml.
-- Verification: static registry/graph tests here; real builds for a
-- subset live in tests/extra.sh (GCPKG_EXTRA_DYNAMIC=1).
-- SSH2 on the existing openssl + zlib ports.
-- Upstream is never patched: all adaptation is in this file.

local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "libssh",
    version = "0.11.1",
    license = "LGPL-2.1",
    homepage = "https://www.libssh.org",
    description = "SSH2 client/server library on OpenSSL",
    source = {
        url = "https://codeload.github.com/libssh/libssh-mirror/tar.gz/refs/tags/libssh-0.11.1",
        sha256 = "b43ef9c91b6c3db64e7ba3db101eb89dbe645db63489c19d4f88cf6f84911ec6",
        strip = 1,
    },
    dependencies = {
        "openssl",
        "zlib",
      },
    cmake = {
        defines = {
          UNIT_TESTING = "OFF",
          CLIENT_TESTING = "OFF",
          WITH_EXAMPLES = "OFF",
          WITH_GSSAPI = "OFF",
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
        "ssh",
      },
      binaries = {},
    },
}
