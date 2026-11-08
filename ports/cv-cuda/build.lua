-- cv-cuda 0.19.0 -- ONE library, ONE build.lua + ONE features.yaml.
-- Verification in this sandbox: static (check / graph / ports / externals) (see tests/media.sh).
-- CV-CUDA needs the local CUDA toolkit ('nvidia' SDK port).
-- Upstream is never patched: all adaptation lives in this file.


local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "cv-cuda",
    version = "0.19.0",
    description = "CV-CUDA GPU-accelerated computer vision operators",
    license = "Apache-2.0",
    homepage = "https://github.com/CVCUDA/CV-CUDA",
    source = {
        url = "https://codeload.github.com/CVCUDA/CV-CUDA/tar.gz/refs/tags/v0.19.0",
        sha256 = "8659124529341bdffeb11d88c2ed189a68d5817dd3f77a35248824dd29bd2fed",
        strip = 1,
    },
    dependencies = {
        "nvidia",
      },
    cmake = {
        defines = {
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
        "nvcv",
      },
      binaries = {},
    },
}
