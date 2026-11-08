-- libdwarf 0.11.1 -- ONE library, ONE build.lua + ONE features.yaml.
-- Verification: static registry/graph tests in tests/r10.sh; real
-- builds in GCPKG_R10_DYNAMIC=1 ./tests/r10.sh.
-- DWARF reader; `compression` feature pulls zlib + zstd.
-- Upstream is never patched: all adaptation is in this file.

local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "libdwarf",
    version = "0.11.1",
    license = "LGPL-2.1",
    homepage = "https://github.com/davea42/libdwarf-code",
    description = "DWARF debug information reader",
    source = {
        url = "https://codeload.github.com/davea42/libdwarf-code/tar.gz/refs/tags/v0.11.1",
        sha256 = "dfd24db87c354b3ba6fa72d29a481014f81768fea15ddcde96a8a938b1557c17",
        strip = 1,
    },
    dependencies = {},
    cmake = {
        defines = {
          BUILD_TESTING = "OFF",
          BUILD_SHARED = "OFF",
          BUILD_NON_SHARED = "ON",
          BUILD_DWARFDUMP = "OFF",
          BUILD_DWARFGEN = "OFF",
          BUILD_DWARFEXAMPLE = "OFF",
          ENABLE_DECOMPRESSION = "OFF",
          DO_TESTING = "OFF",
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
        "dwarf",
      },
      binaries = {},
    },
}
