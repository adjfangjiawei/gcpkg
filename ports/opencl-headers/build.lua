-- opencl-headers 2026.05.29 -- gcpkg port definition.
-- Khronos OpenCL API headers; C probe, no compiled runtime dependency.

local recipe = require("gcpkg.recipe")

return recipe.header {
    name = "opencl-headers",
    version = "2026.05.29",
    license = "Apache-2.0",
    homepage = "https://github.com/KhronosGroup/OpenCL-Headers",
    description = "Khronos OpenCL API headers; header-only C probe",
    source = {
        url = "https://codeload.github.com/KhronosGroup/OpenCL-Headers/tar.gz/refs/tags/v2026.05.29",
        sha256 = "d9e6c48357de5002da11ce45de600e0c3ffe6ab4f628a3b9fe2b38603161658a",
        strip = 1,
    },
    dependencies = {},
    header = {
        headers = {
            { src = "CL", dst = "CL" },
          },
        include = "CL/cl.h",
        flags = {
            "-std=c11",
          },
        license_files = {
            "LICENSE",
          },
        cxx = false,
    },
    exports = {
      includes = { "@PREFIX@/include" },
      libdirs = { "@LIBDIR@" },
      libs = {},
      binaries = {},
    },
}
