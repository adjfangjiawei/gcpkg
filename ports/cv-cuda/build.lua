-- cv-cuda 0.19.0 -- gcpkg port definition.
-- CV-CUDA needs the local CUDA toolkit ('nvidia' SDK port).


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
