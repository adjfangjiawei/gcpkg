-- vulkan 1.4.363.0 -- ONE library, ONE build.lua + ONE features.yaml.
-- Verification in this sandbox: static (check / graph / ports / externals) (see tests/media.sh).
-- Khronos Vulkan-Loader; depends on vulkan-headers and the managed cmake tool port.
-- Upstream is never patched: all adaptation lives in this file.


local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "vulkan",
    version = "1.4.363.0",
    description = "Khronos Vulkan ICD loader",
    license = "Apache-2.0",
    homepage = "https://github.com/KhronosGroup/Vulkan-Loader",
    source = {
        url = "https://codeload.github.com/KhronosGroup/Vulkan-Loader/tar.gz/refs/tags/vulkan-sdk-1.4.363.0",
        sha256 = "941eff558fc74f248745fb7df367640cf89a8457f216dae498a74ae14b6ba6f7",
        strip = 1,
    },
    dependencies = {
        "vulkan-headers",
        "cmake",
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
        "vulkan",
      },
      binaries = {},
    },
}
