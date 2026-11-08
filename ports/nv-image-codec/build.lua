-- nv-image-codec 0.10.0 -- ONE library, ONE build.lua + ONE features.yaml.
-- Verification in this sandbox: static (check / graph / ports / externals) (see tests/media.sh).
-- nvImageCodec requires CUDA >= 12.1 and optionally CV-CUDA (its samples). Both are declared gcpkg ports.
-- Upstream is never patched: all adaptation lives in this file.


local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "nv-image-codec",
    version = "0.10.0",
    description = "NVIDIA nvImageCodec GPU/CPU image codecs",
    license = "Apache-2.0",
    homepage = "https://github.com/NVIDIA/nvImageCodec",
    source = {
        url = "https://codeload.github.com/NVIDIA/nvImageCodec/tar.gz/refs/tags/v0.10.0",
        sha256 = "d36466e2366585795ecd967c9e8eb62618eb155e6030a9b0f2c3274f260a14f0",
        strip = 1,
    },
    dependencies = {
        "nvidia",
        "cv-cuda",
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
        "nvimgcodec",
      },
      binaries = {},
    },
}
