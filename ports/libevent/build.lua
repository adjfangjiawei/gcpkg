-- libevent 2.1.13 -- ONE library, ONE build.lua + ONE features.yaml.
-- Verification: static registry/graph tests here; real builds for a
-- subset live in tests/linux-base.sh (GCPKG_BASE_DYNAMIC=1).
-- Event loop, linked against the existing openssl port.
-- Upstream is never patched: all adaptation is in this file.

local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "libevent",
    version = "2.1.13",
    license = "BSD-3-Clause",
    homepage = "https://libevent.org",
    description = "Event notification library",
    source = {
        url = "https://codeload.github.com/libevent/libevent/tar.gz/refs/tags/release-2.1.13-stable",
        sha256 = "1a0885e17dc78afbaeddf13cf849f9238bbc24acdc178464a0d1934d7c5ffbd5",
        strip = 1,
    },
    dependencies = {
        "openssl",
      },
    cmake = {
        defines = {
          EVENT__DISABLE_TESTS = "ON",
          EVENT__DISABLE_BENCHMARK = "ON",
          EVENT__DISABLE_SAMPLES = "ON",
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
        "event",
        "event_core",
        "event_extra",
        "event_openssl",
      },
      binaries = {},
    },
}
