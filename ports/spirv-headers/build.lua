-- spirv-headers vulkan-sdk-1.4.363.0 -- gcpkg port definition.
-- Khronos SPIR-V headers; include/spirv becomes the installed include/spirv.

local recipe = require("gcpkg.recipe")

return recipe.header {
    name = "spirv-headers",
    version = "vulkan-sdk-1.4.363.0",
    license = "MIT",
    homepage = "https://github.com/KhronosGroup/SPIRV-Headers",
    description = "Khronos SPIR-V machine-readable and C/C++ headers",
    source = {
        url = "https://codeload.github.com/KhronosGroup/SPIRV-Headers/tar.gz/refs/tags/vulkan-sdk-1.4.363.0",
        sha256 = "5b3a0d099f5c7649e29c0938476c462e71d66ad89a0bde42fa1ba3eb476956c9",
        strip = 1,
    },
    dependencies = {},
    header = {
        headers = {
            { src = "include/spirv", dst = "spirv" },
          },
        include = "spirv/unified1/spirv.hpp11",
        flags = {
            "-std=c++17",
          },
        license_files = {
            "LICENSE",
          },
    },
    exports = {
      includes = { "@PREFIX@/include" },
      libdirs = { "@LIBDIR@" },
      libs = {},
      binaries = {},
    },
}
