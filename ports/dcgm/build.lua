-- dcgm 4.7.0 -- ONE library, ONE build.lua + ONE features.yaml.
-- Verification in this sandbox: static (check / graph / ports / externals) (see tests/media.sh).
-- NVIDIA DCGM open-core tree; needs the local CUDA driver/toolkit ('nvidia' SDK port) and vendor-only diagnostics components.
-- Upstream is never patched: all adaptation lives in this file.


local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "dcgm",
    version = "4.7.0",
    description = "NVIDIA Data Center GPU Manager",
    license = "Apache-2.0",
    homepage = "https://github.com/NVIDIA/DCGM",
    source = {
        url = "https://codeload.github.com/NVIDIA/DCGM/tar.gz/refs/tags/v4.7.0",
        sha256 = "9a25e64b0117a2492d4fb22eb700553c2cb662cc7660bf820ce95c25a3309fe0",
        strip = 1,
    },
    dependencies = {
        "nvidia",
      },
    cmake = {
        defines = {
          BUILD_TESTING = "OFF",
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
        "dcgm",
      },
      binaries = {},
    },
}
