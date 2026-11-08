-- vulkan-headers 1.4.363.0 -- ONE library, ONE build.lua + ONE features.yaml.
-- Verification in this sandbox: static (check / graph / ports / externals) (see tests/media.sh).
-- Khronos Vulkan-Headers: header/registry-only CMake install, feeds the loader.
-- Upstream is never patched: all adaptation lives in this file.


local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "vulkan-headers",
    version = "1.4.363.0",
    description = "Khronos Vulkan API headers and registry",
    license = "Apache-2.0",
    homepage = "https://github.com/KhronosGroup/Vulkan-Headers",
    source = {
        url = "https://codeload.github.com/KhronosGroup/Vulkan-Headers/tar.gz/refs/tags/vulkan-sdk-1.4.363.0",
        sha256 = "4a078be12bef21cfebc09d878b77a63cff9d68f899254a0b00d0e37ef73e7f7e",
        strip = 1,
    },
    dependencies = {},
    cmake = {
        defines = {},
        args = {},
    },
    exports = {
      includes = {
        "@PREFIX@/include",
      },
      libdirs = {
        "@LIBDIR@",
      },
      libs = {},
      binaries = {},
    },
}
