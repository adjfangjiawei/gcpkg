-- libgit2 1.9.1 -- ONE library, ONE build.lua + ONE features.yaml.
-- Static registry checks in tests/r12.sh; GCPKG_R12_DYNAMIC=1 builds it for real.
-- libgit2; real bottom-up zlib dependency, no bundled zlib.
-- Upstream is never patched: all adaptation lives in this file.

local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "libgit2",
    version = "1.9.1",
    license = "GPL-2.0-with-linking-exception",
    homepage = "https://libgit2.org",
    description = "Portable Git core library; consumes the zlib port",
    source = {
        url = "https://codeload.github.com/libgit2/libgit2/tar.gz/refs/tags/v1.9.1",
        sha256 = "14cab3014b2b7ad75970ff4548e83615f74d719afe00aa479b4a889c1e13fc00",
        strip = 1,
    },
    dependencies = {
        "zlib",
      },
    cmake = {
        defines = function(ctx)
            local d = ctx.dep("zlib")
            local t = {
              USE_BUNDLED_ZLIB = "OFF",
              USE_HTTPS = "OFF",
              USE_SSH = "OFF",
              USE_ICONV = "OFF",
              USE_NTLMCLIENT = "OFF",
              BUILD_TESTS = "OFF",
              BUILD_CLI = "OFF",
            }
            if d and d.prefix then t.ZLIB_ROOT = d.prefix end
            return t
        end,
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
        "git2",
      },
      binaries = {},
    },
}
