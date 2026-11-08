-- flatbuffers 24.3.25 -- ONE library, ONE build.lua + ONE features.yaml.
-- Verification: static registry/graph tests in tests/r10.sh; real
-- builds in GCPKG_R10_DYNAMIC=1 ./tests/r10.sh.
-- FlatBuffers serialization; flatc/tests off.
-- Upstream is never patched: all adaptation is in this file.

local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "flatbuffers",
    version = "24.3.25",
    license = "Apache-2.0",
    homepage = "https://github.com/google/flatbuffers",
    description = "Memory-efficient serialization library",
    source = {
        url = "https://codeload.github.com/google/flatbuffers/tar.gz/refs/tags/v24.3.25",
        sha256 = "4157c5cacdb59737c5d627e47ac26b140e9ee28b1102f812b36068aab728c1ed",
        strip = 1,
    },
    dependencies = {},
    cmake = {
        defines = {
          BUILD_TESTING = "OFF",
          FLATBUFFERS_BUILD_TESTS = "OFF",
          FLATBUFFERS_BUILD_GRPCTEST = "OFF",
          FLATBUFFERS_BUILD_FLATBUFFERS = "OFF",
          FLATBUFFERS_BUILD_SHAREDLIB = "OFF",
          FLATBUFFERS_BUILD_FLATLIB = "ON",
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
        "flatbuffers",
      },
      binaries = {},
    },
}
